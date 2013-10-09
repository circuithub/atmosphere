angular.module("directives").directive("graph", function() {
  return {
    restrict: "E",
    scope: {
      shouts: "="
    },
    templateUrl: "dev.html",
    controller: function($scope) {
      return console.log("running!");
    }
  };
});
