_ = require "underscore"
nconf = require "nconf"
elma  = require("elma")(nconf)
bsync = require "bsync"

core = require "./core"
monitor = require "./monitor"

jobWorkers = {}
currentJob = {}


########################################
## SETUP / INITIALIZATION
########################################

###
  jobTypes -- object with jobType values and worker function callbacks as keys; { jobType1: cbDoJobType1, jobType2: .. }
  -- Safe to call this function multiple times. It adds additional job types. If exists, jobType is ignored during update.
  --role: String. 8 character (max) description of this rainCloud (example: "app", "eda", "worker", etc...)
###
exports.init = (role, jobTypes, cbDone) ->    
  #[0.] Initialize
  core.setRole role
  #[1.] Connect to message server    
  core.connect (err) ->      
    if err?
      cbDone err
      return
    #[2.] Publish all jobs we can handle (listen to all queues for these jobs)
    workerFunctions = []    
    for jobType of jobTypes
      if not jobWorkers[jobType]?
        jobWorkers[jobType] = jobTypes[jobType]
        workerFunctions.push bsync.apply exports.listen, jobType, lightning
    bsync.parallel workerFunctions, (allErrors, allResults) ->
      if allErrors?
        cbDone allErrors
        return
      monitor.boot() #log boot time
      cbDone undefined


########################################
## API
########################################

_callbackMQ = (theJob, ticket, errors, result) ->
  header = {job: theJob.job, type: theJob.type, rainCloudID: core.rainID()}
  message = 
    errors: errors
    data: result
  core.publish currentJob[ticket.type].returnQueue, message, header

###
  Reports completed job on a Rain Cloud
  -- ticket: {type: "", job: {name: "", id: "uuid"} }
  -- message: the job response data (message body)
###
exports.doneWith = (ticket, errors, result) =>
  #Sanity checking
  if not core.ready() 
    #TODO: HANDLE THIS BETTER
    elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
    return
  if not currentJob[ticket.type]?
    #TODO: HANDLE THIS BETTER
    elma.error "noTicketWaiting", "Ticket for #{ticket.type} has no current job pending!" 
    return
  #Retrieve the interal state for this job
  theJob = currentJob[ticket.type]
  #Console
  numJobsNext = if theJob.next? then theJob.next.length else 0
  elma.info "[doneWith]", "#{ticket.type}-#{ticket.name}; #{numJobsNext} jobs follow."
  #No more jobs in the chain
  if numJobsNext is 0  
    _callbackMQ theJob, ticket, errors, result if theJob.callback
    return #all done processing this job chain!
  #More jobs in the chain
  else
    if errors?
      #Abort chain if errors occurred
      _callbackMQ theJob, ticket, errors, result      
    else
      #Fire callback if specified
      _callbackMQ theJob, ticket, errors, result if theJob.callback
      #Get next job in the chain
      nextJob = theJob.next.shift()
      #Cascade results (merge incoming results from last job with incoming user data for new job)      
      nextData = (nextJob.data ?= {})
      nextData[theJob.type] = result
      #Format and Submit next job
      payload = 
        data: nextData
        next: theJob.next
      headers = 
        job: 
          name: theJob.job.name
          id: theJob.job.id
        returnQueue: theJob.returnQueue
        callback: nextJob.callback
      core.submit nextJob.type, payload, headers
  
  #Done with this specific job in the job chain
  delete currentJob[ticket.type] #done with current job, update state
  process.nextTick () ->
    core.acknowledge theJob.type, (err) ->
      if err?
        #TODO: HANDLE THIS BETTER
        elma.error "cantAckError", "Could not send ACK", theJob, err 
        return
      monitor.jobComplete()

###
  Subscribe to persistent incoming jobs in the queue (non-exclusively)
  (Queue will continue to exist even if no-one is listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err)  
###
exports.listen = (type, cbExecute, cbListening) =>
  core.listen type, cbExecute, false, true, true, cbListening

###
  report RainCloud performance statistics
###
exports.count = () ->
  return monitor.stats()

###
  Object of current jobs (queue names currently being processed by this worker)
  Returns an array of queue names (job types) with active jobs in it
###
exports.currentJobs = () ->
  return Object.keys currentJob


########################################
## STOCK ROUTERS
########################################

rpcWorkers = {} #When using the simple router, stores the actual worker functions the router should invoke

###
  Simple direct jobs router. Fastest/easiest way to get RPC running in your app.
  --Takes in job list and wraps your function in (ticket, data) -> doneWith(..) behavior
###
basic = (taskName, functionName) ->
  rpcWorkers[taskName] = functionName #save work function
  return _basicRouter

_basicRouter = (ticket, data) ->
  elma.info "[JOB] #{ticket.type}-#{ticket.name}-#{ticket.step}"
  ticket.data = data if data? #add job data to ticket
  #Execute (invoke work function)
  rpcWorkers[ticket.type] ticket, (errors, results) ->
    # Release lower stack frames
    process.nextTick () ->
      exports.doneWith ticket, errors, results

exports.routers =
  basic: basic



########################################
## INTERNAL OPERATIONS
########################################

###
  Receives work to do messages on cloud and dispatches
  Messages are dispatched to the callback function this way:
    function(ticket, data) ->
###
lightning = (message, headers, deliveryInfo) =>
  if currentJob[deliveryInfo.queue]?
    #PANIC! BAD STATE! We got a new job, but haven't completed previous job yet!
    elma.error "duplicateJobAssigned", "Two jobs were assigned to atmosphere.rainCloud at once! SHOULD NOT HAPPEN.", currentJob, deliveryInfo, headers, message
    return
  #Hold this information internal to atmosphere
  currentJob[deliveryInfo.queue] = {
    type: deliveryInfo.queue
    job: headers.job # job = {name:, id:}    
    returnQueue: headers.returnQueue
    next: message.next
    callback: headers.callback
  }
  #Release this information to the work function (dispatch job)
  ticket = 
    type: deliveryInfo.queue
    name: headers.job.name
    id: headers.job.id
  jobWorkers[deliveryInfo.queue] ticket, message.data
