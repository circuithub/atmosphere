_          = require "underscore"
nconf      = require "nconf"
bsync      = require "bsync"

core       = require "./core"
monitor    = require "./monitor"
rainMaker  = require "./rain.maker"

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
exports.init = (role, url, token, rainBuckets, cbDone) =>    

  #[1.] Connect  
  connect = (next) ->
    core.init role, url, token, (error) =>
      if error?
        cbDone error
        return
      next()

      
  #[2.] List all rainBuckets we can handle (--> listen to all queues for these jobs)
  register = (next) ->
    #--Register with Sky
    core.refs().rainCloudsRef.child("#{core.rainID()}/status").set 
      rainBuckets: Object.keys rainBuckets  
      cpu: [0,0,0]  
    #--Store Callback Functions
    jobWorkers[rainBucket] = cbExecute for rainBucket, cbExecute of rainBuckets
    next()

  #[3.] Register to submit jobs (so workers can submit jobs)
  submit = (next) ->
    rainMaker.start (error) ->
      if error?
        cbDone error
        return
      monitor.boot() #log boot time
      next()

  #[4.] Listen for new jobs
  listen = (next) ->
    core.refs().rainCloudsRef.child("#{core.rainID()}/todo").on "child_added", (snapshot) ->
      #--Log start
      core.refs().rainDropsRef.child("#{snapshot.name()}/log").set {when: core.now(), who: core.rainID()}
      #--Go get actual RainDrop
      core.refs().rainDropsRef.child("#{snapshot.name()}").once "value", (snapshot) ->
        console.log "\n\n\n=-=-=[cloud.listen]2", snapshot.name(), snapshot.val(), "\n\n\n" #xxx
        #Execute job
        lightning snapshot.val().job?.type, snapshot.name(), snapshot.val(), (error) ->
          if error?
            #Job failed to be dispatched (right now, this can't happen, or isn't detected)
            console.log "[atmosphere]", "EDISPATCH", error      
            return
    next()

  connect -> register -> submit -> listen -> cbDone()
    


########################################
## API
########################################

###
  Reports completed job on a Rain Cloud
  -- ticket: {type: "", name: "", id: "uuid"}
  -- message: the job response data (message body)
###
exports.doneWith = (ticket, errors, response) =>
  console.log "\n\n\n=-=-=[doneWith](currentJob)", Object.keys(currentJob), "\n\n\n" #xxx
  rainDrop = undefined
  rainDropID = ticket.id

  #Sanity checking
  sanity = (next) ->
    if not core.ready() 
      #TODO: HANDLE THIS BETTER
      console.log "[atmosphere]", "ENOFIRE", "Not connected to #{core.urlLogSafe} yet!" 
      return
    if not currentJob[ticket.type]?
      #TODO: HANDLE THIS BETTER
      console.log "[atmosphere]", "ENOTICKET", "Ticket for #{ticket.type} has no current job pending!", Object.keys currentJob
      return
    next()

  #Retrieve the interal state for this job
  getDrop = (next) ->
    core.refs().rainDropsRef[rainDropID].once "value", (snapshot) ->
    rainDrop = snapshot.val()
    next()

  #Write to rainDrop
  write = (next) ->
    if rainDrop.next?
      #-- jobChain, write results forward
      if errors?
        #-- errors occurred, report forward through all remaining jobs
        cascadeError rainDropID, errors, () ->
        return
      #-- No errors occurred, report forward
      core.refs().rainDropsRef.child("#{rainDrop.next}/data/previous/#{rainDrop.job.type}").set response, () ->
        #-- Schedule next job in chain
        core.refs().skyRef.child("todo/#{rainDrop.next}").set true, () ->
          closeRainDrop rainDropID
          return
    else
      core.refs().rainDropsRef.child(rainDropID).update
        result:
          errors: errors
          response: response
        log:
          stop: core.log "stop"
      , () ->
        closeRainDrop rainDropID

###
  Done with this job. Perform closing actions.
###
closeRainDrop = (rainDropID) ->
  delete currentJob[ticket.type] #done with current job, update state  
  monitor.jobComplete()
  core.refs().skyRef.child("todo/#{rainDropID}").remove() 

###
  Report error forward to all remaining jobs in the chain
###
cascadeError = (rainDropID, errors, cbReported) ->
  core.refs().rainDropsRef.child(rainDropID).once "value", (snapshot) ->
    #--Write error
    core.refs().rainDropsRef.child(rainDropID).update
      result:
        errors: errors
      log:
        stop: core.log "stop"
    #--Next
    rainDrop = snapshot.val()
    if not rainDrop.next?
      cbReported undefined
      return
    cascadeError rainDrop.next, errors, cbReported
      




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
  console.log "[JOB] #{ticket.type}-#{ticket.name}-#{ticket.step}"
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
  currentJob[rainBucket] = rainDropID
  #Release this information to the work function (dispatch job)
  ticket = 
    type: rainBucket
    name: rainDrop.job.name
    id: rainDropID
  jobWorkers[rainBucket] ticket, rainDrop.data
  #Log
  monitor.log rainDropID, "start"
  cbDispatched()
