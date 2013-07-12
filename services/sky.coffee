_          = require "underscore"
atmosphere = require "../index"
{check}    = require "validator"
nconf      = require "nconf"

stats    = {}
messages = []
reports  = {}
workers  = {}


########################################
## CONNECT
########################################

exports.init = (cbReady) =>
  disTasks = undefined
  nextStep = undefined

  #[1.] Load Task List
  disTaskList = (next) ->
    atmosphere.core.connect nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return
      nextStep = next
      atmosphere.core.refs().baseRef.child("disTaskList").once "value", loadList
  
  #[2.] Retrieved DIS Task List
  loadList = (snapshot) ->
    disTasks = snapshot.val()
    nextStep()
  
  #[3.] Register as a Rain Maker
  rainInit = (next) ->
    atmosphere.rainMaker.init "spark", nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->      
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return
      next()

  #[4.] Load tasks / Begin monitoring
  registerTasks = (next) ->    
    for task of disTasks
      if disTasks[task].type is "dis"
        if disTasks[task].period > 0
          console.log "[init] Will EXECUTE #{task}", JSON.stringify disTasks[task]
          #guiltySpark task, disTasks[task].data, disTasks[task].timeout, disTasks[task].period
        else
          console.log "[init] IGNORING #{task} (no period specified)"
    next()

  #[3.] Handle task scheduling
  brokerTasks = (next) ->
    listenBase()
    listenRainBuckets()
    next()

  #[4.] Monitor for dead workers
  recoverFailures = (next) ->
    #TODO    
    next()

  disTaskList -> rainInit -> registerTasks -> brokerTasks -> recoverFailures -> cbReady()



########################################
## STATE MANAGEMENT
########################################

###
  Attach (and maintain) current state of specified atmosphere data type
  -- Keeps data.dataType up to date
###
rain = undefined
listen = (dataType) =>
  atmosphere.core.refs()["#{dataType}Ref"].on "value", (snapshot) -> 
    rain[dataType] = snapshot.val()
    console.log "=-=-=[sky.listen]", atmosphere.core.refs()["#{dataType}Ref"].toString(), snapshot.val() #xxx
listenBase = () ->
  rain = 
    rainClouds: listen "rainClouds"
    rainDrops: listen "rainDrops"
    rainMakers: listen "rainMakers"

###
  Handle the addition (and removal) of rainBuckets (rainDrop types)
###
listenRainBuckets = () ->
  #New rainBucket (job type) installed (added)
  atmosphere.core.refs().rainDropsRef.child("todo").on "child_added", (snapshot) ->
    console.log "\n\n\n=-=-=[listenRainBuckets.add]", snapshot.name(), "\n\n\n" #xxx
    atmosphere.core.refs().rainDropsRef.child("todo/#{snapshot.name()}").startAt().limit(1).on "child_added", schedule
  #rainBucket (job type) removed (deleted)
  atmosphere.core.refs().rainDropsRef.child("todo").on "child_removed", (snapshot) ->
    atmosphere.core.refs().rainDropsRef.child("todo/#{snapshot.name()}").off() #remove all listeners/callbacks



########################################
## SCHEDULING
########################################

###
  Schedule new job
###
schedule = (rainDropSnapshot) ->  
  #--Update data
  rainDrop = rainDropSnapshot.val()
  rainDropID = rainDropSnapshot.name()
  rainBucket = rainDrop?.job?.type
  #TODO (jonathan) Sanity check this; delete if malformed; report error
  console.log "[sky]", "IWIN", "Scheduling a #{rainBucket} job."
  #Move job to worker queue
  assignTo = assign rainBucket
  if not assignTo?
    #No rainCloud available to do the work -- put the job back on the queue
    console.log "=-=-=[sky]", "INOONE", "No worker available for #{rainBucket} job."         
  else
    #Assign the rainDrop to the specified rainCloud
    atmosphere.core.refs().rainCloudsRef.child("#{assignTo}/todo/#{rainBucket}/#{rainDropSnapshot.name()}/start").set atmosphere.core.now()
    #Register to handle job completion
    atmosphere.core.refs().rainCloudsRef.child("#{assignTo}/todo/#{rainBucket}/#{rainDropSnapshot.name()}").on "child_added", (stopSnapshot) ->
      return if stopSnapshot.name() isnt "stop"
      #TODO: analytics
      atmosphere.core.refs().rainCloudsRef.child("#{assignTo}/todo/#{rainBucket}/#{rainDropSnapshot.name()}").remove()
  
###
  Load balance the rainClouds. 
  >> Determine which rainCloud (worker) should get the next rainDrop (job) in the specified rainBucket
  >> Results are only valid immediately after function returns (data gets stale quickly)
  >> Synchronous Function
  >> Returns undefined if no rainClouds available
  -- rainBucket: String. Name of the bucket
###
assign = (rainBucket) ->
  candidates = {id:[], metric:[]}
  console.log "\n\n\n=-=-=[assign]", rain.rainClouds, "\n\n\n" #xxx
  for rainCloudID, rainCloudData of rain.rainClouds 
    console.log "\n\n\n=-=-=[assign]", rainBucket, rainCloudData.status.rainBuckets, rainBucket in rainCloudData.status.rainBuckets, not rainCloudData.todo?[rainBucket]?, "\n\n\n" #xxx 
    #-- if registered for these job types (listening to this bucket) and not currently busy with a job from this bucket...
    if rainBucket in rainCloudData.status.rainBuckets and not rainCloudData.todo?[rainBucket]?
      console.log "\n\n\n=-=-=[assign]", "INSIDE!", rainCloudID, "\n\n\n" #xxx
      candidates.id.push rainCloudID
      candidates.metric.push Number rainCloudData.status.cpu?[0]
  return undefined if candidates.id.length is 0 #no available rainClouds (workers)
  mostIdle = _.min candidates.metric  
  asignee = candidates.id[_.indexOf candidates.metric, mostIdle]
  console.log "\n\n\n=-=-=[assign]", "ASSIGNED:", mostIdle, asignee, candidates.id, candidates.metric, "\n\n\n" #xxx
  return asignee










