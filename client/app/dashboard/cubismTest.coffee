angular.module('atmosphere', ['ui-bootstrap'])
  .controller 'cubismTest', ['$scope', 'metricsGraph', ($scope, $metricsGraph) ->
    #bare minimum options
    $scope.metricsOptions = 
      graph:
        type: "horizon"
      metrics:
        type: "cube"
        url: ""
        expressions: [ "sum(requests)" ]

  ]

    
    
  
