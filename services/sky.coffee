_          = require "underscore"
atmosphere = require "../index"
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
    atmosphere.core.refs().rainCloudsRef.on "child_added", reschedule 
    #Retry scheduling after a worker finishes a job
    atmosphere.core.refs().skyRef.child("done").on "child_added", reschedule
    #Debug Investigation Monitor -- #xxx
    monitor = () ->
      console.log "=-=-=[monitor]", toSchedule.length #xxx
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
  return #xxx
  rainCloud = undefined
  getCloud = (next) ->
    atmosphere.core.refs().rainCloudsRef.child("#{rainCloudID}").once "value", (snapshot) ->
      rainCloud = snapshot.val()
      if rainCloud.todo?
        for eachJob of rainCloud.todo
          atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/assign").remove()
          atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/start").remove()
          atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log/stop").remove()
          atmosphere.core.refs().rainDropsRef.child("#{eachJob}/log").push atmosphere.core.log rainCloudID, "recover"
          atmosphere.core.refs().skyRef.child("todo/#{eachJob}").set false
      next()
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
  rainBucket = undefined
  asignee = undefined
  
  todoRainDropIDs = []

  getTasks = () ->
    next = getTask
    atmosphere.core.refs().skyRef.child("todo").once "value", (snapshot) ->
      console.log "\n\n\n=-=-=[getTasks]", atmosphere.core.refs().skyRef.child("todo").toString(), snapshot.name(), snapshot.val(), "\n\n\n" #xxx
      if not snapshot.val()?
        next()
        return
      todoRainDropIDs = Object.keys snapshot.val()
      console.log "\n\n\n=-=-=[GET TASKS!!!]", todoRainDropIDs.length, "\n\n\n" #xxx
      next()

  getTask = () ->
    next = getDrop
    rainDropID = todoRainDropIDs.shift()
    console.log "\n\n\n=-=-=[GET TASK !!!]", rainDropID, "\n\n\n" #xxx
    if not rainDropID?
      console.log "[sky]", "IALLDONE", "Nothing to do..."
      anyMore()
      return
    console.log "[sky]", "ISCHEDULE", "Scheduling #{rainDropID}"
    next()     

  getDrop = () ->
    next = getClouds
    console.log "\n\n\n=-=-=[GET DROP]", rainDropID, "\n\n\n" #xxx
    atmosphere.core.refs().rainDropsRef.child(rainDropID).once "value", (rainDropSnapshot) ->
      rainDrop = rainDropSnapshot.val()
      rainBucket = rainDrop.job.type
      next()
  
  getClouds = () ->
    next = plan
    console.log "\n\n\n=-=-=[getClouds1]", rainDropID, "\n\n\n" #xxx
    atmosphere.core.refs().rainCloudsRef.once "value", (snapshot) ->
      console.log "\n\n\n=-=-=[getClouds2]", rainDropID, "\n\n\n" #xxx
      rainClouds = snapshot.val()
      next()

  plan = () ->
    next = assign
    asignee = undefined #reset
    console.log "\n\n\n=-=-=[PLAN]", rainDropID, "\n\n\n" #xxx
    if not rainClouds?
      next() #No workers online so no one available for this job... =(
      return
    candidates = {id:[], metric:[]}
    for rainCloudID, rainCloudData of rainClouds 
      if not rainCloudData.status.rainBuckets? or rainBucket in rainCloudData.status.rainBuckets #This cloud handles this type of job
        if not workingOn rainCloudID, rainClouds, rainBucket 
          #-- This worker is available to take the job
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
      #No rainCloud available to do the work -- put the job back on the queue
      console.log "[sky]", "INOONE", "No worker available for #{rainBucket} job."         
      next()
      return
    console.log "[sky]", "IBOSS", "Scheduling #{rainDropID} --> #{asignee}"
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
      console.log "\n\n\n=-=-=[TRANSACTION!!!]", rainDropID, asignee, "\n\n\n" #xxx
      #[2.] /sky: Mark the rainDrop as assigned
      atmosphere.core.refs().skyRef.child("todo/#{rainDropID}").remove()
      #[3.] /rainDrop: Log the assignment
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
  getTasks()



###
  Is the specified rainCloud already working on a job (drop) of this type (bucket)
###
workingOn = (rainCloudID, rainClouds, rainBucket) ->
  try
    for workingDropID, workingBucket of rainClouds[rainCloudID].todo
      return true if workingBucket is rainBucket
  catch e
    console.log "\n\n\n=-=-=[workingOn]", e, "\n\n\n" #xxx
  return false
