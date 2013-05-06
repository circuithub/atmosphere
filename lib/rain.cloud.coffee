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
    console.log "\n\n\n=-=-=[rc.init]", 1, "\n\n\n" #xxx
      
    if err?
      cbDone err
      return
    #[2.] Publish all jobs we can handle (listen to all queues for these jobs)
    workerFunctions = []    
    for jobType of jobTypes
      if not jobWorkers[jobType]?
        jobWorkers[jobType] = jobTypes[jobType]
        workerFunctions.push bsync.apply exports.listen, jobType, lightning
    console.log "\n\n\n=-=-=[rc.init]", 2, "\n\n\n" #xxx
    bsync.parallel workerFunctions, (allErrors, allResults) ->
      console.log "\n\n\n=-=-=[rc.init]", 3, allErrors, allResults, "\n\n\n" #xxx
      if allErrors?
        cbDone allErrors
        return
      monitor.boot() #log boot time
      cbDone undefined


########################################
## API
########################################

###
  Reports completed job on a Rain Cloud
  -- ticket: {type: "", job: {name: "", id: "uuid"} }
  -- message: the job response data (message body)
###
exports.doneWith = (ticket, errors, data) =>
  if not core.ready() 
    #TODO: HANDLE THIS BETTER
    elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
    return
  if not currentJob[ticket.type]?
    #TODO: HANDLE THIS BETTER
    elma.error "noTicketWaiting", "Ticket for #{ticket.type} has no current job pending!" 
    return
  header = {job: currentJob[ticket.type].job, type: currentJob[ticket.type].type, rainCloudID: core.rainID()}
  message = 
    errors: errors
    data: data
  core.publish currentJob[ticket.type].returnQueue, message, header
  theJob = currentJob[ticket.type]
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
  Array of current jobs (queue names currently being processed by this worker)
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
  elma.info "[JOB] #{ticket.type}-#{ticket.job.name}-#{ticket.step}"
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
    elma.error "duplicateJobAssigned", "Two jobs were assigned to atmosphere.cloud server at once! SHOULD NOT HAPPEN.", currentJob, deliveryInfo, headers, message
    return
  currentJob[deliveryInfo.queue] = {
    type: deliveryInfo.queue
    job: headers.job # job = {name:, id:}
    data: message
    returnQueue: headers.returnQueue
  }
  jobWorkers[deliveryInfo.queue]({type: deliveryInfo.queue, job: headers.job}, currentJob[deliveryInfo.queue].data)
