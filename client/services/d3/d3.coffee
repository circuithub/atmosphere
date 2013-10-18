#Wraps a reference to d3 in an angular service.
#
#This service wraps only an api reference and
#requires the d3 script to be loaded.

angular.module('atmosphere')
  .service 'd3', ['$q', ($q) ->
      deferred = $q.defer()
      deferred.resolve window.d3

      return {
        d3: () ->
          return deferred.promise
      }
  ]
