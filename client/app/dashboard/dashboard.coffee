angular.module("atmosphere", ["ui.bootstrap"])
  .controller "TabsDemoCtrl", [ 
    "$scope", ($scope) ->
      $scope.tabs = [
        title: "Dynamic Title 1-hi"
        content: "Dynamic content 1"
      ,
        title: "Dynamic Title 2"
        content: "Dynamic content 2"
        disabled: true
      ]

      $scope.alertMe = ->
        setTimeout ->
          alert "You've selected the alert tab!"

      $scope.navType = "pills"
  ]
