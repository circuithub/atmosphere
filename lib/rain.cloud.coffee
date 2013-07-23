_          = require "underscore"
_s         = require "underscore.string"
nconf      = require "nconf"
bsync      = require "bsync"
objects    = require "objects"

core       = require "./core"
monitor    = require "./monitor"
rainMaker  = require "./rain.maker"

jobWorkers = {}


########################################
## SETUP / INITIALIZATION
########################################

###
  Initialize Rain Cloud
  >> Safe to call this function multiple times. It adds additional job types. If exists, jobType is ignored during update.
  -- role: String. 8 character (max) description of this rainCloud (example: "app", "eda", "worker", etc...)
  -- options: 
     -- url: Firebase URL (slash terminated). Ex. https://atmosphere.firebaseio-demo.com/
     -- token: Firebase server authentication token (from Forge, Auth tab)
     -- exclusive: This rain cloud will only process one job at a time
  -- rainBuckets: object with jobType values and worker function callbacks as keys; { jobType1: cbDoJobType1, jobType2: .. }
###
exports.init = (role, options, rainBuckets, cbDone) =>    
  #[0.] Default Options
  options.exclusive ?= true
  
  #[1.] Connect  
  connect = (next) ->
    core.init role, "rainCloud", options.url, options.token, (error) =>
      if error?
        cbDone error
        return
      core.refs().connectedRef.on "value", (snap) ->
        if snap.val() is true #We're connected (or reconnected)
          onlineRef = core.refs().skyRef.child("recover/#{core.rainID()}")
          onlineRef.onDisconnect().set core.now()
          onlineRef.remove()
      next()

      
  #[2.] List all rainBuckets we can handle (--> listen to all queues for these jobs)
  register = (next) ->
    #--Register with Sky
    core.refs().rainCloudsRef.child("#{core.rainID()}/status").set 
      rainBuckets: _.map Object.keys(rainBuckets), (eachBucket) -> _s.dasherize(eachBucket).toLowerCase()
      load: [0,0,0]  
      completed: 0
      exclusive: options.exclusive
    #--Store Callback Functions
    jobWorkers[rainBucket] = cbExecute for rainBucket, cbExecute of rainBuckets
    next()

  #[3.] Register to submit jobs (so workers can submit jobs)
  submit = (next) ->
    rainMaker.start (error) ->
      if error?
        cbDone error
        return
      monitor.boot() #log boot time; start system monitoring
      next()

  #[4.] Listen for new jobs
  listen = (next) ->
    core.refs().rainCloudsRef.child("#{core.rainID()}/todo").on "child_added", (snapshot) ->
      #--Log start
      monitor.log snapshot.name(), "start"
      #--Go get actual RainDrop
      core.refs().rainDropsRef.child("#{snapshot.name()}").once "value", (snapshot) ->
        #Execute job
        lightning snapshot.val().job?.type, snapshot.name(), snapshot.val(), (error) ->
          if error?
            #Job failed to be dispatched (right now, this can't happen, or isn't detected)
            console.log "[atmosphere]", "EDISPATCH", error      
            return
    next()

  #[5.] I'm online (start scheduling me)
  online = (next) ->
    core.refs().skyRef.child("online/#{core.rainID()}").set true
    next()

  connect -> register -> submit -> listen -> online -> cbDone()
    


########################################
## (1) EXECUTE INCOMING JOBS
########################################

###
  Receives work to do messages on cloud and dispatches
  Messages are dispatched to the callback function this way:
    function(ticket, data) ->
###
lightning = (rainBucket, rainDropID, rainDrop, cbDispatched) =>
  console.log "[atmosphere]", "ISTRIKE", rainBucket, rainDropID, JSON.stringify rainDrop
  #Release this information to the work function (dispatch job)
  ticket = 
    type: rainBucket
    name: rainDrop.job.name
    id: rainDropID
  jobWorkers[rainBucket] ticket, rainDrop.data
  cbDispatched()



########################################
## (2) WRAP EXECUTE FUNCTIONS (ROUTERS)
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
## (3) PROCESS COMPLETED JOBS
########################################

###
  Reports completed job on a Rain Cloud
  -- ticket: {type: "", name: "", id: "uuid"}
  -- message: the job response data (message body)
###
exports.doneWith = (ticket, errors, response) =>
  rainDrop = undefined
  rainDropID = ticket.id

  #Sanity checking
  sanity = (next) ->
    console.log "[atmosphere]", "IDONE1", "sanity", rainDropID
    if not core.ready() 
      #TODO: HANDLE THIS BETTER
      console.log "[atmosphere]", "ENOFIRE", "Not connected to #{core.urlLogSafe()} yet!" 
      return    
    next()

  #Retrieve the interal state for this job
  getDrop = (next) ->
    console.log "[atmosphere]", "IDONE2", "getDrop", rainDropID
    core.refs().rainDropsRef.child(rainDropID).once "value", (snapshot) ->
      console.log "[atmosphere]", "IDONE2.1", "getDrop", rainDropID
      rainDrop = snapshot.val()
      next()
    , (something) ->
      console.log "\n\n\n=-=-=[IDONE2 ERROR]", something, "\n\n\n" #xxx
      process.exit 44

  #Write to rainDrop
  write = (next) ->
    console.log "[atmosphere]", "IDONE3", "write", rainDropID
    #-- Write results (TODO make atomic)
    core.refs().rainDropsRef.child(rainDropID).update
      result:
        errors: if errors? then objects.onlyData(errors) else null
        response: if response? then objects.onlyData(response) else null
    console.log "[atmosphere]", "IDONE3.1", "write", rainDropID
    if rainDrop.next?
      #-- jobChain, write results forward
      if errors?
        #-- errors occurred, report forward through all remaining jobs
        console.log "[atmosphere]", "IDONE3.2", "write", rainDropID, errors
        cascadeError rainDropID, errors, () ->
        return
      #-- No errors occurred, report forward
      core.refs().rainDropsRef.child("#{rainDrop.next}/data/previous/#{rainDrop.job.type}").set objects.onlyData(response), () ->
        #-- Schedule next job in chain
        core.refs().skyRef.child("todo/#{rainDrop.next}").set true, () ->
          closeRainDrop rainDropID, rainDrop
          return
    else
      closeRainDrop rainDropID, rainDrop

  sanity -> getDrop -> write()


###
  Done with this job. Perform closing actions.
  #-- TODO make atomic
###
closeRainDrop = (rainDropID, rainDrop) ->
  a = (next) ->
    console.log "[atmosphere]", "IDONE4", rainDropID #xxx
    core.refs().rainDropsRef.child("#{rainDropID}/log/stop").set core.log(rainDropID, "stop"), next
  b = (next) ->
    console.log "[atmosphere]", "IDONE5", rainDropID #xxx
    monitor.jobComplete()
    next()
  c = (next) ->
    console.log "[atmosphere]", "IDONE6", rainDropID #xxx
    core.refs().rainCloudsRef.child("#{core.rainID()}/done/#{rainDropID}").set true, next
  d = (next) ->
    console.log "[atmosphere]", "IDONE7", rainDropID #xxx
    core.refs().rainCloudsRef.child("#{core.rainID()}/todo/#{rainDropID}").remove next  
  e = (next) ->
    console.log "[atmosphere]", "IDONE8", rainDropID #xxx
    core.refs().skyRef.child("done/#{rainDropID}").set true, next
  f = (next) ->
    console.log "[atmosphere]", "IDONE9", rainDropID #xxx
    core.refs().rainCloudsRef.child("#{core.rainID()}/done/#{rainDropID}").remove next
  g = () ->  
    console.log "[atmosphere]", "IDONE10", rainDropID #xxx
  a -> b -> c -> d -> e -> f -> g()

###
  Report error forward to all remaining jobs in the chain
###
cascadeError = (rainDropID, errors, cbReported) ->
  core.refs().rainDropsRef.child(rainDropID).once "value", (snapshot) ->
    #--Write error (TODO make atomic)
    core.refs().rainDropsRef.child(rainDropID).update
      result:
        errors: errors
    core.refs().rainDropsRef.child("#{rainDropID}/log/stop").set core.log rainDropID, "stop"
    #--Next
    rainDrop = snapshot.val()
    if not rainDrop.next?
      cbReported undefined
      return
    cascadeError rainDrop.next, errors, cbReported
      








