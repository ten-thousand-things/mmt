var Dashboard = function () {
  $(".tab").on("click", function () {
    var selector = $(this).data("selector");
    $(".tab").removeClass("active");
    $(this).addClass("active");
    $(".dashboard-widgets").children().addClass("hidden");
    $("section[data-selector=" + selector + "]").removeClass("hidden");
  });

  var transactionSelect = $("#transactionSelect");
  var memberSelect = $("#memberSelect");
  $.each([transactionSelect, memberSelect], function () {
    $(this).on("propertychange change keyup", function (e) {
      $(this).closest("form").submit();
    });
  });
}