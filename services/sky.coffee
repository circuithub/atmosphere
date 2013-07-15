_          = require "underscore"
atmosphere = require "../index"
{check}    = require "validator"
nconf      = require "nconf"



########################################
## CONNECT
########################################

###
  The URL of the server we're connected to
###
exports.server = () ->
  return atmosphere.core.urlLogSafe

exports.init = (cbReady) =>
  console.log "[sky]", "IKNIT", "Initializing Sky..."

  weather = undefined
  nextStep = undefined

  #[1.] Connect to Firebase
  connect = (next) ->
    console.log "[sky]", "IKNIT1", "connect"
    atmosphere.core.connect nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return
      next()

  #[1.] Load Task List
  loadWeather = (next) ->
    console.log "[sky]", "IKNIT2", "loadWeather"
    nextStep = next
    atmosphere.core.refs().weatherRef.once "value", loadList
  
  #[2.] Retrieved Weather Pattern
  loadList = (snapshot) ->
    console.log "[sky]", "IKNIT3", "loadList"
    weather = snapshot.val()
    nextStep()
  
  #[3.] Register as a Rain Maker
  rainInit = (next) ->
    console.log "[sky]", "IKNIT4", "rainInit"
    atmosphere.rainMaker.init "sky", nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->      
      if err?
        console.log "[ECONNECT]", "Could not connect to atmosphere.", err
        cbReady err
        return
      next()

  #[4.] Load tasks / Begin monitoring
  registerTasks = (next) ->    
    console.log "[sky]", "IKNIT5", "registerTasks"
    for task of weather
      if weather[task].type is "dis"
        if weather[task].period > 0
          console.log "[init] Will EXECUTE #{task}", JSON.stringify weather[task]
          #guiltySpark task, weather[task].data, weather[task].timeout, weather[task].period
        else
          console.log "[init] IGNORING #{task} (no period specified)"
    next()

  #[5.] Handle task scheduling
  brokerTasks = (next) ->
    console.log "[sky]", "IKNIT6", "brokerTasks"
    listen "rainClouds" #monitor rainClouds
    listen "sky" #monitor sky
    atmosphere.core.refs().skyRef.child("todo").on "child_added", (snapshot) ->
      schedule snapshot.name()
    atmosphere.core.refs().skyRef.child("recover").on "child_added", (snapshot) ->
      recover snapshot.name() #TODO
    next()

  #[6.] Monitor for recovery scenarios (dead workers, rescheduling, etc)
  recoverFailures = (next) ->
    console.log "[sky]", "IKNIT7", "recoverFailures"
    #Retry scheduling when a new worker comes online
    atmosphere.core.refs().rainCloudsRef.on "child_added", reschedule 
    #Retry scheduling after a worker finishes a job
    atmosphere.core.refs().skyRef.child("done").on "child_added", reschedule
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
rain = {}
listen = (dataType) =>
  atmosphere.core.refs()["#{dataType}Ref"].on "value", (snapshot) -> 
    console.log "[listen]", snapshot.name()
    rain[dataType] = snapshot.val()
 


########################################
## RECOVERY
########################################

reschedule = () ->
  if rain.sky?.todo?
    schedule rainDropID for rainDropID, scheduled of rain.sky.todo when not scheduled


########################################
## SCHEDULING
########################################
  
###
  Schedule the specifed rainDrop
  -- Called when entry added to /sky/todo
###
schedule = (rainDropID) ->
  console.log "[sky]", "ISCHEDULE", "Scheduling #{rainDropID}" 

  #--Collect rainDrop data
  rainDrop = undefined
  rainBucket = undefined
  asignee = undefined
  
  getDrop = (next) ->
    console.log "[sky]", "ISCHEDULE1", "getDrop"
    atmosphere.core.refs().rainDropsRef.child(rainDropID).once "value", (rainDropSnapshot) ->
      rainDrop = rainDropSnapshot.val()
      rainBucket = rainDrop.job.type
      next()
  
  getClouds = (next) ->
    atmosphere.core.refs().rainCloudsRef.once "value", (snapshot) ->
      rain.rainClouds = snapshot.val()
      next()

  plan = (next) ->
    console.log "[sky]", "ISCHEDULE2", "plan"    
    if not rain.rainClouds?
      next() #No workers online so no one available for this job... =(
      return
    candidates = {id:[], metric:[]}
    for rainCloudID, rainCloudData of rain.rainClouds 
      console.log "[sky][plan]", rainCloudID, rainCloudData, rainCloudData?.todo
      if rainBucket in rainCloudData.status.rainBuckets #This cloud handles this type of job
        if not workingOn rainCloudID, rainBucket 
          #-- This worker is available to take the job
          candidates.id.push rainCloudID
          candidates.metric.push Number rainCloudData.status.load?[0]
    if candidates.id.length is 0 #no available rainClouds (workers)
      next()
      return
    mostIdle = _.min candidates.metric  
    asignee = candidates.id[_.indexOf candidates.metric, mostIdle]
    next()

  assign = (next) ->
    console.log "[sky]", "ISCHEDULE3", "assign"
    if not asignee?
      #No rainCloud available to do the work -- put the job back on the queue
      console.log "[sky]", "INOONE", "No worker available for #{rainBucket} job."         
      return
    console.log "[sky]", "IBOSS", "Scheduling a #{rainBucket} job."
    #[1.] /rainCloud: Assign the rainDrop to the indicated rainCloud
    atmosphere.core.refs().rainCloudsRef.child("#{asignee}/todo/#{rainDropID}").set rainBucket
    #[2.] /sky: Mark the rainDrop as assigned
    atmosphere.core.refs().skyRef.child("todo/#{rainDropID}").set true
    #[3.] /rainDrop: Log the assignment
    atmosphere.monitor.log rainDropID, "assign", asignee

  getDrop -> getClouds -> plan -> assign()



###
  Is the specified rainCloud already working on a job (drop) of this type (bucket)
###
workingOn = (rainCloudID, rainBucket) ->
  try
    for workingDropID, workingBucket of rain.rainClouds[rainCloudID].todo
      return true if workingBucket is rainBucket 
  catch e
    console.log "\n\n\n=-=-=[workingOn]", e, "\n\n\n" #xxx
  return false
