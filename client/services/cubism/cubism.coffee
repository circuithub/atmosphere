#Wraps a reference to cubism in an angular service.
#
#This service wraps only an api reference and
#requires the cubism script to be loaded.

angular.module('atmosphere')
  .service 'cubism', ['$q', ($q) ->
      deferred = $q.defer()
      deferred.resolve window.cubism

      return {
        cubism: () ->
          return deferred.promise
      }
  ]
