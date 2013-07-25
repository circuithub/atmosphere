_          = require "underscore"
atmosphere = require "../../index"
nconf      = require "nconf"
spark      = require "./spark"



########################################
## CONNECT
########################################

###
  The URL of the server we're connected to
###
exports.server = () ->
  return atmosphere.core.urlLogSafe()

exports.init = (cbReady) =>
  console.log "[sky]", "IKNIT", "Initializing Sky..."

  weather = undefined

  #[1.] Register as a Rain Maker
  rainInit = (next) ->
    console.log "\n\n\n=-=-=[sky.init]", nconf.get("FIREBASE_URL"), "\n\n\n" #xxx
    atmosphere.rainMaker.init "sky", nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->      
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return
      next()
  
  #[2.] Retrieved Weather Pattern
  loadWeather = (next) ->
    atmosphere.weather.pattern (error, data) ->
      weather = data
      next()

  #[4.] Load tasks / Begin monitoring
  registerTasks = (next) ->    
    for task of weather
      if weather[task].type is "dis"
        if weather[task].period > 0
          console.log "[init] Will EXECUTE #{task} every #{weather[task].period} SECONDS"
          spark.register task, weather[task].data, weather[task].timeout, weather[task].period
        else
          console.log "[init] IGNORING #{task} (no period specified)"
    next()

  #[5.] Handle task scheduling
  brokerTasks = (next) ->    
    #Listen for new jobs
    atmosphere.core.refs().skyRef.child("todo").on "child_added", (snapshot) ->
      schedule()
    #Listen for crashed rainClouds (and recover them)
    atmosphere.core.refs().skyRef.child("recover").on "child_added", (snapshot) ->
      recover snapshot.name(), snapshot.val()
    #Listen for dead rainMakers (and remove them)
    atmosphere.core.refs().skyRef.child("remove").on "child_added", (snapshot) ->
      remove snapshot.name(), snapshot.val()
    next()

  #[6.] Monitor for recovery scenarios (dead workers, rescheduling, etc)
  recoverFailures = (next) ->
    #Retry scheduling when a new worker comes online
    atmosphere.core.refs().skyRef.child("online").on "child_added", (snapshot) ->
      atmosphere.core.refs().skyRef.child("online").child(snapshot.name()).remove()
      reschedule()
    #Retry scheduling after a worker finishes a job
    atmosphere.core.refs().skyRef.child("done").on "child_added", reschedule
    #Debug Investigation Monitor -- #xxx
    monitor = () ->
      #console.log "=-=-=[monitor]", toSchedule.length #xxx
      setTimeout () ->
        monitor() 
      , 1000
    monitor()
    next()

  rainInit -> loadWeather -> registerTasks -> brokerTasks -> recoverFailures -> cbReady()



########################################
## RECOVERY
########################################

reschedule = () ->
  console.log "[sky]", "ITRYAGAIN", "Rescheduling..."
  schedule()

###
  Recover a failed rainCloud
  -- rainCloudID
  -- disconnectedAt - UNIX epoch time, milliseconds
###
recover = (rainCloudID, disconnectedAt) ->
  rainCloud = undefined
  getCloud = (next) ->
    atmosphere.core.refs().rainCloudsRef.child("#{rainCloudID}").once "value", (snapshot) ->
      rainCloud = snapshot.val()
      toRecover =[]
      toRecover.push eachJob for eachJob of rainCloud.todo if rainCloud.todo?
      toRecover.push eachJob for eachJob of rainCloud.done if rainCloud.done?
      toRecover = _.uniq toRecover #remove duplicates (handle edge case)
      retry eachJob for eachJob in toRecover
      next()
  retry = (eachJob) ->
    atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/assign").remove()
    atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/start").remove()
    atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/stop").remove()
    atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log").push atmosphere.core.log rainCloudID, "recover"
    atmosphere.core.refs().skyRef.child("todo/#{eachJob}").set false
  record = (next) ->
    #TODO
    next()
  cleanup = (next) ->
    atmosphere.core.refs().rainCloudsRef.child(rainCloudID).remove()
    atmosphere.core.refs().skyRef.child("recover/#{rainCloudID}").remove()
  getCloud -> record -> cleanup()

###
  Remove a failed rainMaker
  -- rainMakerID
###
remove = (rainMakerID, disconnectedAt) ->
  rainMaker = undefined
  getMaker = (next) ->
    atmosphere.core.refs().rainMakersRef.child("#{rainMakerID}").once "value", (snapshot) ->
      rainMaker = snapshot.val()
      next()
  record = (next) ->
    #TODO
    next()
  cleanup = (next) ->
    atmosphere.core.refs().rainMakersRef.child(rainMakerID).remove()
    atmosphere.core.refs().skyRef.child("remove/#{rainMakerID}").remove()
  getMaker -> record -> cleanup()



########################################
## SCHEDULING
########################################
  
###
  Schedule
  -- Called when new job posted to queue
  -- Called when new worker comes online
  -- Called when first booted
###
schedulingNow = false
toSchedule = []
schedule = () ->

  #--Collect rainDrop data
  rainDropID = undefined
  rainDrop = undefined
  rainClouds = undefined

  
  asignee = undefined
  
  rainDrops = undefined #snapshot of all jobs awaiting scheduling
  todoRainDropIDs = []

  rainBucket = undefined
  rainDropGroup = undefined

  getState = () ->
    next = gotState
    toSchedule = [] #reset pending schedule iterations since we're about to cache state at this point and schedule them
    cbCounter = 0
    allSnapshots = {}
    atmosphere.core.refs().skyRef.child("todo").once "value", (snapshot) ->
      allSnapshots.drops = snapshot
      cbCounter++
      next(allSnapshots) if cbCounter is 2
    atmosphere.core.refs().rainCloudsRef.once "value", (snapshot) ->
      allSnapshots.clouds = snapshot
      cbCounter++
      next(allSnapshots) if cbCounter is 2
  
  gotState = (allSnapshots) ->
    #console.log "\n\n\n=-=-=[GOT STATE]", JSON.stringify(allSnapshots.clouds.val()), "\n\n\n" #xxx
    next = getTask
    if not allSnapshots?.drops?
      console.log "[sky]", "IALLDONE2", "Nothing to do..."
      return
    if not allSnapshots?.clouds?
      console.log "[sky]", "INOONE1", "No workers online."         
      return
    if allSnapshots.drops.val()?
      rainDrops = allSnapshots.drops.val()
      todoRainDropIDs = Object.keys allSnapshots.drops.val()
    if allSnapshots.clouds.val()?
      rainClouds = allSnapshots.clouds.val()
    next()
  
  getTask = () ->
    next = plan    
    rainDropID = todoRainDropIDs.shift()
    if not rainDropID?
      console.log "[sky]", "IALLDONE", "Nothing to do..."
      anyMore()
      return
    #console.log "[sky]", "ISCHEDULE", "Scheduling #{rainDropID}"    
    rainDropGroup = rainDrops[rainDropID].group
    rainBucket = rainDrops[rainDropID].type
    rainDropGroup ?= "main" #default to everything in one group
    rainBucket ?= atmosphere.core.getBucket rainDropID #extract job type from job name as a fallback for malformed data
    next()     
  
  plan = () ->
    next = assign
    asignee = undefined #reset
    if not rainClouds?
      next() #No workers online so no one available for this job... =(
      return
    candidates = {id:[], metric:[]}
    for rainCloudID, rainCloudData of rainClouds 
      #--Does this cloud handle this bucket? Either no buckets defined or specific bucket matches
      if not rainCloudData.status.rainBuckets? or rainBucket in rainCloudData.status.rainBuckets
        #--Is this worker available to take the job?
        if not workingOn rainCloudID, rainClouds, rainBucket           
          candidates.id.push rainCloudID
          candidates.metric.push Number rainCloudData.status.load?[0]
    if candidates.id.length is 0 #no available rainClouds (workers)
      next()
      return
    mostIdle = _.min candidates.metric  
    asignee = candidates.id[_.indexOf candidates.metric, mostIdle]
    next()

  assign = () ->
    next = nextDrop
    if not asignee?
      #console.log "[sky]", "INOONE2", "No worker available for #{rainBucket} job."         
      next()
      return
    console.log "[sky]", "IBOSS", "Scheduling #{rainDropID} --> #{asignee}"
    #[0.] /rainCould: Prematurely (latency-compensation) log the assignment in local cache (we'll detect failures in the next scheduler pass)
    rainClouds[asignee].todo ?= {}
    rainClouds[asignee].todo[rainDropID] = rainBucket
    updateFunction = (rainCloud) ->
      #Do we still exist?
      return undefined if not rainCloud?.log?.start?
      #Are we already working in this bucket?
      for eachDrop, eachBucket of rainCloud?.todo
        return undefined if eachBucket is rainBucket
      #All good, let's make changes
      rainCloud.todo = {} if not rainCloud.todo?
      rainCloud.todo[rainDropID] = rainBucket
      return rainCloud
    onComplete = (error, committed, snapshot) ->
      if error?
        console.log "[sky]", "EGATZ", "Transaction scheduling #{rainDropID} --> #{asignee} failed abnormally!", error
        next()
        return
      if not committed
        console.log "[sky]", "ELATE", "Transaction scheduling #{rainDropID} --> #{asignee} failed rainCloud is busy or offline!"
        next()
        return
      #[2.] /sky: Mark the rainDrop as assigned
      atmosphere.core.refs().skyRef.child("todo/#{rainDropID}").remove()
      #[3.] /rainDrop: Log the assignment (Firebase)
      atmosphere.monitor.log rainDropID, "assign", asignee
      #[4.] Get next drop and repeat
      next()
    #[1.] /rainCloud: Assign the rainDrop to the indicated rainCloud
    atmosphere.core.refs().rainCloudsRef.child(asignee).transaction updateFunction, onComplete, false
    
  nextDrop = () ->
    #-- LOOP until we've attempted to schedule all pending jobs
    setImmediate () ->
      getTask()

  anyMore = (next) ->
    schedulingNow = false
    if toSchedule.length > 0
      setImmediate () ->
        schedule toSchedule.shift() #decrement and execute schedule loop again

  #Arbitrate (synchronous)
  if schedulingNow
    console.log "[sky]", "INOSCHEDULE", "Defer scheduling..."
    toSchedule.push true #we're busy scheduling something else, add this to the wait queue
    return    
  schedulingNow = true
  getState() #Let's do this!



###
  Is the specified rainCloud already working on a job (drop) of this type (bucket)
  TODO -- Investigate if this is performing correctly
###
workingOn = (rainCloudID, rainClouds, rainBucket) ->
  try
    if rainClouds[rainCloudID].status.exclusive 
      if rainClouds[rainCloudID].todo? and Object.keys(rainClouds[rainCloudID].todo).length > 0 #only work on one job at a time in exclusive mode
        return true
    for workingDropID, workingBucket of rainClouds[rainCloudID].todo
      return true if workingBucket.toLowerCase() is rainBucket.toLowerCase()
  catch e
    console.log "\n\n\n=-=-=[workingOn]", e, "\n\n\n" #xxx
  return false
