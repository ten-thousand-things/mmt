# frozen_string_literal: true

class Coin < ApplicationRecord
  extend FriendlyId
  friendly_id :code, use: :slugged

  BTC_SUBDIVISION = 8

  has_many :source_transactions, as: :source,
                                 class_name: "Transactions::Base",
                                 dependent: :restrict_with_error

  has_many :destination_transactions, as: :destination,
                                      class_name: "Transactions::Base",
                                      dependent: :restrict_with_error

  has_many :asset_events, class_name: "Events::Asset",
                          dependent: :restrict_with_error

  has_many :liability_events, class_name: "Events::Liability",
                              dependent: :restrict_with_error

  has_many :members, through: :liability_events

  has_many :equity_events, class_name: "Events::Equity",
                           dependent: :restrict_with_error

  has_many :contributors, through: :equity_events, source: :member

  scope :ordered, -> { order(:code) }
  scope :crypto, -> { where(crypto_currency: true) }
  scope :fiat, -> { where.not(crypto_currency: true) }
  scope :not_self, ->(coin_id) { where.not(id: coin_id) }
  scope :not_btc, -> { where.not(code: "BTC") }

  attr_readonly :code

  validates :code, uniqueness: { case_sensitive: true },
                   format: { with: /\A[a-zA-Z0-9_\.]*\Z/ }

  validates :slug, uniqueness: { case_sensitive: true }

  validates :subdivision, :code, presence: true
  validates :subdivision, numericality: { greater_than_or_equal_to: 0 }

  validates :assets, numericality: { greater_than_or_equal_to: 0 }

  def display_name
    name
  end

  def crypto?
    crypto_currency
  end

  def fiat?
    !crypto_currency
  end

  def system_total_display
    Coin.sum do |coin|
      Utils.to_decimal(coin.assets * coin.btc_rate, coin.subdivision) / btc_rate
    end
  end

  def assets
    asset_events.sum(:assets)
  end

  def assets_display
    Utils.to_decimal(assets, subdivision)
  end

  def liability
    liability_events.sum(:liability)
  end

  def liability_display
    Utils.to_decimal(liability, subdivision)
  end

  def equity
    equity_events.sum(:equity)
  end

  # ===> Live value and rate

  def value(iso_currency)
    btc_rate * (1.0 / fiat_btc_rate(iso_currency))
  end

  # @return The amount of this currency that buys one BTC
  def btc_rate
    crypto_currency ? crypto_btc_rate : fiat_btc_rate
  end

  def self.btc
    find_by(code: "BTC")
  end

  private

  def fiat_btc_rate(iso_currency = nil)
    1.0 / BigDecimal.new(
      coinbase_rates["data"]["rates"][iso_currency || code]
    )
  end

  def coinbase_rates
    Rails.cache.fetch("coinbase_rates", expires_in: 30.minutes, race_condition_ttl: 5.seconds) do
      HTTParty.get("https://api.coinbase.com/v2/exchange-rates?currency=BTC").parsed_response
    end
  end

  def bittrex_rates
    Rails.cache.fetch("bittrex_rates", expires_in: 30.minutes, race_condition_ttl: 5.seconds) do
      HTTParty.get("https://bittrex.com/api/v1.1/public/getmarketsummaries").parsed_response
    end
  end

  def crypto_btc_rate
    return 1.0 if code == "BTC"
    # %%TODO%% We need a way to deal with missing codes so it doesn't cascade through and break the system
    # raise BittrexError, "Bittrex does not supply rates for #{code}" unless coins_by_bittrex.include? code
    bittrex_rates["result"].compact.find do |market|
      market["MarketName"] == "BTC-#{code}"
    end["Bid"]
  end

  def coins_by_bittrex
    bittrex_rates["result"].compact.map do |market|
      market["MarketName"].split("-").last
    end
  end

  def ensure_subdivision_multiple_of_ten
    return unless subdivision
    return unless (subdivision % 10).zero?
    errors.add :subdivision, "must be a multiple of 10"
  end
end
