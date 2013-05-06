rpcWorkers = {} #When using the simple router, stores the actual worker functions the router should invoke

###
  Simple direct jobs router. Fastest/easiest way to get RPC running in your app.
  --Takes in job list and wraps your function in (ticket, data) -> doneWith(..) behavior
###
exports.basic = (taskName, functionName) ->
  rpcWorkers[taskName] = functionName #save work function
  return _basicRouter

_basicRouter = (ticket, data) ->
  elma.info "[JOB] #{ticket.type}-#{ticket.job.name}-#{ticket.step}"
  ticket.data = data if data? #add job data to ticket
  #Execute (invoke work function)
  rpcWorkers[ticket.type] ticket, (errors, results) ->
    # Release lower stack frames
    process.nextTick () ->
      exports.doneWith ticket, errors, results




