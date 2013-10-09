angular.module("directives").directive "graph", () ->
  restrict: "E"
  scope: 
    shouts: "="
  templateUrl: "dev.html"
  controller: ($scope) ->
    console.log "running!"