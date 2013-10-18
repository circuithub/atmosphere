angular.module("atmosphere", ["ui.bootstrap"]).controller("TabsDemoCtrl", [
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
