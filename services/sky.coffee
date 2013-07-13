_          = require "underscore"
atmosphere = require "../index"
{check}    = require "validator"
nconf      = require "nconf"



########################################
## CONNECT
########################################

exports.init = (cbReady) =>
  weather = undefined
  nextStep = undefined

  #[1.] Connect to Firebase
  connect = (next) ->
    atmosphere.core.connect nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return

  #[1.] Load Task List
  loadWeather = (next) ->
    nextStep = next
    atmosphere.core.refs().baseRef.child("weatherPattern").once "value", loadList
  
  #[2.] Retrieved Weather Pattern
  loadList = (snapshot) ->
    weather = snapshot.val()
    nextStep()
  
  #[3.] Register as a Rain Maker
  rainInit = (next) ->
    atmosphere.rainMaker.init "sky", nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->      
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
    listen "rainClouds" #monitor rainClouds
    atmosphere.core.refs().skyRef.child("todo").on "child_added", schedule
    atmosphere.core.refs().skyRef.child("crashed").on "child_added", recover
    next()

  #[4.] Monitor for dead workers
  recoverFailures = (next) ->
    #TODO    
    next()

  connect -> loadWeather -> rainInit -> registerTasks -> brokerTasks -> recoverFailures -> cbReady()



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
 


########################################
## SCHEDULING
########################################
  
###
  Schedule new job
###
schedule = (todoSnapshot) ->
  #--Collect rainDrop data
  rainDrop = undefined
  rainDropID = todoSnapshot.name()
  rainBucket = undefined
  asignee = undefined
  
  getDrop = (next) ->
    atmosphere.core.refs().rainDrops.child(rainDropID).once "value", (rainDropSnapshot) ->
      rainDrop = rainDropSnapshot.val()
      rainBucket = rainDrop.job.type
      #--Is this rainDrop already assigned to a rainCloud?
      if rainDrop.log.assign? and rain.rainClouds[rainDrop.log.assign.what]?
        #-- Exact job already assigned. Do nothing. Recovery occurred.
        console.log "[sky]", "WREBOOT", "#{rainBucket}/#{rainDropID} is already assigned and in progress. Sky rebooted?"
        return
      next()

  plan = (next) ->
    candidates = {id:[], metric:[]}
    for rainCloudID, rainCloudData of rain.rainClouds 
      if rainBucket in rainCloudData.status.rainBuckets #This cloud handles this type of job
        if not workingOn rainCloudID, rainBucket 
          #-- This worker is available to take the job
          candidates.id.push rainCloudID
          candidates.metric.push Number rainCloudData.status.cpu?[0]
    return if candidates.id.length is 0 #no available rainClouds (workers)
    mostIdle = _.min candidates.metric  
    asignee = candidates.id[_.indexOf candidates.metric, mostIdle]
    next()

  assign = (next) ->
    if not asignee?
      #No rainCloud available to do the work -- put the job back on the queue
      console.log "[sky]", "INOONE", "No worker available for #{rainBucket} job."         
      return
    console.log "[sky]", "IBOSS", "Scheduling a #{rainBucket} job."
    #[1.] Assigne the rainDrop to the indicated rainCloud
    atmosphere.core.refs().rainCloudsRef.child("#{asignee}/todo/#{rainDropSnapshot.name()}").update rainDropSnapshot.val()
    #[2.] Mark the rainDrop as assigned
    atmosphere.core.refs().rainDropsRef.child("#{rainDropID}/log/assign").set {when: atmosphere.core.now(), what: asignee, who: atmosphere.core.rainID()}

  getDrop -> plan -> assign()



###
  Is the specified rainCloud already working on a job (drop) of this type (bucket)
###
workingOn = (rainCloudID, rainBucket) ->
  try
    for workingDropID of rain.rainClouds.rainCloudID.todo
      return true if rain.rainDrops.workingDropID.job.type is rainBucket 
  catch e
    console.log "\n\n\n=-=-=[workingOn]", e, "\n\n\n" #xxx
  return false
