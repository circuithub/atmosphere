_ = require "underscore"
nconf = require "nconf"
elma  = require("elma")(nconf)
bsync = require "bsync"

core = require "./core"
monitor = require "./monitor"
rainMaker = require "./rain.maker"

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
exports.init = (role, url, token, jobTypes, cbDone) =>    
  #[1.] Initialize
  core.init role, url, token, (error) =>
    if error?
      cbDone error
      return
    #[2.] Subscribe to all jobs we can handle (listen to all queues for these jobs)
    workerFunctions = []    
    for jobType, jobFunction of jobTypes
      if not jobWorkers[jobType]?        
        workerFunctions.push bsync.apply @listen, jobType, lightning
    bsync.parallel workerFunctions, (allErrors, allResults) ->
      if allErrors?
        cbDone allErrors
        return      
      #[3.] Register to submit jobs (so workers can submit jobs)
      rainMaker.start (error) ->
        if error?
          cbDone error
          return
        monitor.boot() #log boot time
        cbDone undefined

      


########################################
## API
########################################

_callbackMQ = (theJob, ticket, errors, result) ->
  rainDropResponse = {}
  rainDropResponse[theJob.job.id] =
    job: theJob.job
    type: theJob.type
    rainCloudID: core.rainID()
    response:  
      errors: if errors? then errors else null
      data: result
  core.refs().rainMakersRef.child("#{currentJob[ticket.type].returnQueue}/done/").set rainDropResponse

###
  Reports completed job on a Rain Cloud
  -- ticket: {type: "", name: "", id: "uuid"}
  -- message: the job response data (message body)
###
exports.doneWith = (ticket, errors, result) =>
  console.log "\n\n\n=-=-=[doneWith](currentJob)", Object.keys(currentJob), "\n\n\n" #xxx
  #Sanity checking
  if not core.ready() 
    #TODO: HANDLE THIS BETTER
    console.log "[atmosphere]", "ENOFIRE", "Not connected to #{core.urlLogSafe} yet!" 
    return
  if not currentJob[ticket.type]?
    #TODO: HANDLE THIS BETTER
    console.log "[atmosphere]", "ENOTICKET", "Ticket for #{ticket.type} has no current job pending!", Object.keys currentJob
    return
  #Retrieve the interal state for this job
  theJob = currentJob[ticket.type]
  #Console
  numJobsNext = if theJob.next?.chain? then theJob.next.chain.length else 0
  elma.info "[atmosphere]", "IDONEWITH", "#{ticket.type}-#{ticket.name}; #{numJobsNext} jobs follow. Callback? #{theJob.callback}"
  #No more jobs in the chain
  if numJobsNext is 0  
    _callbackMQ theJob, ticket, errors, result if theJob.callback    
  #More jobs in the chain
  else
    if errors?
      #Abort chain if errors occurred
      _callbackMQ theJob, ticket, errors, result      
    else
      #Fire callback if specified
      _callbackMQ theJob, ticket, errors, result if theJob.callback
      #Get next job in the chain
      nextJob = theJob.next.chain.shift()
      #Cascade results (merge incoming results from last job with incoming user data for new job)      
      nextData = (nextJob.data ?= {})
      nextData[theJob.type] = result
      #Format and Submit next job
      payload = 
        data: nextData
        next: theJob.next.chain
      headers = 
        job: 
          name: theJob.job.name
          id: theJob.job.id #don't generate a new jobID (same job still)
          type: nextJob.type
        returnQueue: theJob.returnQueue
        callback: nextJob.callback
      core.submit nextJob.type, payload, headers
  #Done with this specific job in the job chain
  delete currentJob[ticket.type] #done with current job, update state  
  core.refs().rainCloudsRef.child("#{core.rainID()}/todo/#{ticket.type}/#{ticket.id}").remove()      
  monitor.jobComplete()

###
  Subscribe to persistent incoming jobs in the queue (non-exclusively)
  (Queue will continue to exist even if no-one is listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err)  
###
exports.listen = (rainBucket, cbExecute, cbListening) =>
  #--Sanity Check
  if not core.ready() 
    cbListening new Error "[atmosphere] ECONNECT Not connected to Firebase yet."
    return  
  #--Register Callback
  jobWorkers[rainBucket] = jobFunction
  #--Register Bucket (inform scheduling engine we accept this type)
  core.refs().rainCloudsRef[core.rainID()].child("status").set 
    rainBuckets: Object.keys jobWorkers  
    cpu: [0,0,0]
  #--Listen for incoming jobs
  rainBucketRef = core.refs().rainDropsRef.child rainBucket
  rainBucketRef.startAt().limit(1).on "child_added", (snapshot) ->
    #Execute job
    cbExecute rainBucket, snapshot.name(), snapshot.val(), (error) ->
      if error?
        #TODO (jonathan) Job failed to be dispatched (right now, this can't happen, or isn't detected)
        console.log "[atmosphere]", "EDISPATCH", error      
        return



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
lightning = (rainBucket, rainDropID, rainDrop, cbDispatched) =>
  console.log "[atmosphere]", "ISTRIKE", rainBucket, rainDropID, rainDrop, Object.keys(currentJob)
  if currentJob[rainBucket]?
    #PANIC! BAD STATE! We got a new job, but haven't completed previous job yet!
    cbDispatched new Error  "duplicateJobAssigned", "Two jobs were assigned to atmosphere.rainCloud at once! SHOULD NOT HAPPEN.", rainBucket, rainDropID, rainDrop
    return
  #Hold this information internal to atmosphere
  currentJob[rainBucket] = 
    type: rainBucket
    job: 
      name: rainDrop.job.name
      id: rainDropID
    returnQueue: rainDrop.next.callbackTo
    next: rainDrop.next
    callback: rainDrop.next.callback
  #Release this information to the work function (dispatch job)
  ticket = 
    type: rainBucket
    name: rainDrop.job.name
    id: rainDropID
  jobWorkers[rainBucket] ticket, rainDrop.data
  cbDispatched()
