# frozen_string_literal: true

module Transactions
  class Base < ApplicationRecord
    include ReadOnlyModel

    self.table_name = "system_transactions"
    self.store_full_sti_class = false

    belongs_to :previous_transaction, class_name: self.name,
                                      foreign_key: :previous_transaction_id,
                                      optional: true

    belongs_to :source, polymorphic: true

    belongs_to :destination, polymorphic: true

    belongs_to :source_coin, class_name: "Coin",
                             foreign_key: :source_coin_id

    belongs_to :destination_coin, class_name: "Coin",
                                  foreign_key: :destination_coin_id

    belongs_to :initiated_by, class_name: "Member",
                              foreign_key: :initiated_by_id,
                              inverse_of: :initiated_transactions

    belongs_to :authorized_by, class_name: "Member",
                               foreign_key: :authorized_by_id,
                               inverse_of: :authorized_transactions

    has_many :events, class_name: "Events::Base",
                      foreign_key: :system_transaction_id,
                      autosave: true,
                      dependent: :restrict_with_error

    has_many :asset_events, class_name: "Events::Asset",
                            foreign_key: :system_transaction_id,
                            autosave: true,
                            dependent: :restrict_with_error

    has_many :liability_events, class_name: "Events::Liability",
                                foreign_key: :system_transaction_id,
                                autosave: true,
                                dependent: :restrict_with_error

    has_many :equity_events, class_name: "Events::Equity",
                             foreign_key: :system_transaction_id,
                             autosave: true,
                             dependent: :restrict_with_error

    before_validation :publish_to_source, :publish_to_destination, on: :create

    def error_message
      errors.full_messages.to_sentence
    end

    TYPES = %w[
      SystemDeposit SystemAllocation SystemWithdrawl
      MemberDeposit MemberAllocation MemberExchange MemberWithdrawl
    ].freeze

    TYPES.each do |type|
      scope type.underscore.to_sym, -> { where type: type }

      define_method "#{type.underscore}?" do
        type == self.type
      end
    end

    scope :ordered, -> { order(created_at: :asc) }
    scope :not_self, ->(sys_transaction) { where.not(id: sys_transaction.id) }
    scope :for_source, ->(source) { where(source: source) }
    scope :for_destination, ->(destination) { where(destination: destination) }

    validates :type, presence: true,
                     inclusion: { in: TYPES }

    validates :initiated_by, presence: true

    validate :correct_previous_transaction,
             :system_sum_to_zero

    def events_sum_display
      [equity_events, liability_events, asset_events].flatten.compact.inject(0) do |total, event|
        entry = Utils.to_decimal(event.entry * event.rate, event.coin.subdivision).round(Coin::BTC_SUBDIVISION)
        event.type == "Asset" ? total -= entry : total += entry
      end
    end

    private

    def system_sum_to_zero
      return true if events_sum_display.zero?
      self.errors.add :system_sum_to_zero, "Invalid transaction"
    end

    def correct_previous_transaction
      return true if previous_transaction.blank? || (previous_transaction.id == referring_transaction.id)
      self.errors.add :previous_transaction, "Invalid previous transaction"
    end

    def not_fiat_to_fiat
      return true unless source_coin.fiat? && destination_coin.fiat?
      self.errors.add :not_fiat_to_fiat, "Fiat to fiat not valid"
    end

    def rates_match
      source_rate_matches = source_rate.to_d.round(Coin::BTC_SUBDIVISION) == source_coin.btc_rate.round(Coin::BTC_SUBDIVISION)
      destination_rate_matches = destination_rate.to_d.round(Coin::BTC_SUBDIVISION) == destination_coin.btc_rate.round(Coin::BTC_SUBDIVISION)
      return true if source_rate_matches && destination_rate_matches
      self.errors.add :rates_match, "Rate has changed. Please resubmit purchase order after checking the new rate"
    end

    def values_match
      source_subdivision = Coin::BTC_SUBDIVISION - source_coin.subdivision
      destination_subdivision = Coin::BTC_SUBDIVISION - destination_coin.subdivision

      source_value = Utils.to_integer(
        (source_quantity * source_rate).round(Coin::BTC_SUBDIVISION),
        source_subdivision
      )
      destination_value = Utils.to_integer(
        (destination_quantity * destination_rate).round(Coin::BTC_SUBDIVISION),
        destination_subdivision
      )
      return true if (source_value - destination_value).zero?
      self.errors.add :values_match, "Invalid purchase"
    end

    def referring_transaction_to_destination
      self.class.ordered.not_self(self).for_destination(destination).last
    end

    def referring_transaction_to_source
      self.class.ordered.not_self(self).for_source(source).last
    end
  end
end
