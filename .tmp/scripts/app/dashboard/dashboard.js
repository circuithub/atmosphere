angular.module("directives", []);

angular.module("atmosphereWeatherStation", ["ui.bootstrap", "directives"]);

console.log("\n\n\n=-=-=[hello world!]", "dev.coffee", "\n\n\n");

angular.module("atmosphereWeatherStation").controller("TabsDemoCtrl", [
  "$scope", function($scope) {
    $scope.tabs = [
      {
        title: "Dynamic Title 1-hi",
        content: "Dynamic content 1"
      }, {
        title: "Dynamic Title 2",
        content: "Dynamic content 2",
        disabled: true
      }
    ];
    $scope.alertMe = function() {
      return setTimeout(function() {
        return alert("You've selected the alert tab!");
      });
    };
    return $scope.navType = "pills";
  }
]);
