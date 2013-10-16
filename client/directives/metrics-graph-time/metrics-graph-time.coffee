###
#This directive instantiates a cubism.js graph with the given options.
#Requirements: cubism.js, d3
#
#Options expected:(rewrite in expected object format)
#metricsGraphTime = {
#  cubism:
#    options: [optional] map of key[,values]
#
#  context:
#    serverDelay: collection lag (ms) [default: 5e3 (5 seconds)]
#    clientDelay: amount of additional time the context waits before incrementally fetching next value.
#      its purpose is to allow charts to be redrawn concurrently.  [default: 5e3 (5 seconds)]
#    step: duration of values (ms) [default: 1e4 (10 seconds)]
#    size: number of values to be displayed [default: 1440 (4 hours at default step)]
#
#
#  graph: 
#    type: type of graph to be rendered. One of ["horizon", "comparison", "axis"].
#    selection: [optional] d3 selection to form which to form a graph
#
#  metrics: [
#    type: type of source used for the metric (one of [])
#    url: url of the server/evaluator the metric will read from
#    expressions: expression to be passed to the metric source.
#      this directive does not check the expressions in any way;
#      the caller must ensure the expressions are parsable by the source. (see Documentation Urls)
#
#  ]
#
#  
# }
#
#Documentation Urls:
#  cubismjs api reference: https://github.com/square/cubism/wiki/API-Reference
#  Cube metric expressions: https://github.com/square/cube/wiki/Queries
#  Graphite target parameters (metric expressions): http://graphite.readthedocs.org/en/latest/render_api.html#target
###
angular.module("directives")
  .directive "metricsGraphTime", [ 'd3', (d3) ->

    events = ["change", "beforechange", "prepare", "focus"]
    return {
      restrict: "A"
      scope: 
        metricsGraphTime: "="
      link: (scope, element, attr) ->
        context = cubism.context()
        cubism.option k,v in metricsGraphTime.cubism.options if metricsGraphTime.cubism.options
        context.serverDelay(metricsGraphTime.context.serverDelay) if metricsGraphTime.context.serverDelay
        context.clientDelay(metricsGraphTime.context.clientDelay) if metricsGraphTime.context.clientDelay
        context.step(metricsGraphTime.context.step) if metricsGraphTime.context.step
        context.size(metricsGraphTime.context.size) if metricsGraphTime.context.size
        
        if metricsGraphTime.graph.type == "horizon"
          graphClassString = ".horizon"
          if metricsGraphTime.graph.selection
            graph = context.horizon(metricsGraphTime.graph.selection)
          else
            graph = context.horizon()
        else if metricsGraphTime.graph.type == "comparison"
          graphClassString = ".comparison"
          if metricsGraphTime.graph.selection
            graph = context.comparison(metricsGraphTime.graph.selection)
          else
            graph = context.comparison()


        for metric in metricsGraphTime.metrics
          if metric.type == "cube"
            graph = graph.metric(cube.metric)
          if metric.type == "graphite"
            graph = graph.metric(graphite.metric)

        metrics = metricsGraphTime.metrics.expressions

        #resolve d3 (service returns a promise) and create the graph
        d3.d3().then (d3) ->
          d3.select(element).append "div"
            .attr "class", "axis"
            .call context.axis().orient "top"

          d3.select(element).append "div"
            .attr "class", "rule"
            .call context.rule()

          d3.select(element).selectAll graphClassString
            .data(metrics)
            .enter().append "div"
            .attr "class", graphClassString
            .call graph

    }]
