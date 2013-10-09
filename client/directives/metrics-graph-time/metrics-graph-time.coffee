angular.module("directives").directive "metricsGraphTime", () ->
  restrict: "A"
  scope: 
    metricsGraphTime: "="
  templateUrl: "metrics-graph-time.html"
  controller: ($scope) ->
    console.log "running!"