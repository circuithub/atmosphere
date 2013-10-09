angular.module("directives").directive("metricsGraphTime", function() {
  return {
    restrict: "A",
    scope: {
      metricsGraphTime: "="
    },
    templateUrl: "metrics-graph-time.html",
    controller: function($scope) {
      return console.log("running!");
    }
  };
});
