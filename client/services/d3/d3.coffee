#wraps d3 in a service so it is easier to use with angular
angular.module('d3', [])
  .factory 'd3Service', ['$document', '$q', '$rootScope', 
    ($document, $q, $rootScope) ->
      q = $q.defer()
      onScriptLoad = () ->
        $rootScope.$apply () -> 
          d.resolve window.d3 

      scriptTag = $document[0].createElement 'script'
      scriptTag.type = 'text/javascript'
      scriptTage.async = true
      scriptTag.src = 'http://d3js.org/d3.v3.min.js'
      scriptTag.onreadystatechange = () ->
        onScriptLoad() if this.readyState == 'complete'

      script.onload = onScriptLoad

      body = $document[0].getElementsByTagName('body')[0]
      body.appendChild scriptTag

      return {
        d3: () ->
          return q.promise
      }
  ]
