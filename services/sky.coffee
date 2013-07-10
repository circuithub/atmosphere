_          = require "underscore"
atmosphere = require "../index"
Firebase = require "firebase"
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
          guiltySpark task, disTasks[task].data, disTasks[task].timeout, disTasks[task].period
        else
          console.log "[init] IGNORING #{task} (no period specified)"
    next()

  #[3.] Handle task scheduling
  brokerTasks = (next) ->
    #atmosphere.rainBucket.listen "disResponse", cortana, cbReady
    next()

  #[4.] Monitor for dead workers
  recoverFailures = (next) ->
    theChief()
    next()

  disTaskList -> rainInit -> registerTasks -> brokerTasks -> recoverFailures -> cbReady()



########################################
## STATE MANAGEMENT
########################################

###
  Attach (and maintain) current state of specified atmosphere data type
  -- Keeps data.dataType up to date
###
listen = (dataType) =>
  atmosphere.core.refs()["#{dataType}Ref"].on "value", (snapshot) -> data[dataType] = snapshot.val()

data = 
  rainClouds: listen "rainClouds"
  rainDrops: listen "rainDrops"
  rainMakers: listen "rainMakers"

###
  Handle the addition (and removal) of rainBuckets (rainDrop types)
###
listenRainBuckets = () ->
  #New rainBucket (job type) installed (added)
  atmosphere.core.refs().rainDropsRef.on "child_added", (snapshot) ->
    atmosphere.core.refs().rainDropsRef.child(snapshot.name()).on "child_added", schedule
  #rainBucket (job type) removed (deleted)
  atmosphere.core.refs().rainDropsRef.on "child_removed", (snapshot) ->
    atmosphere.core.refs().rainDropsRef.child(snapshot.name()).off() #remove all listeners/callbacks



########################################
## OPERATIONS
########################################

###
  Warning: HALO reference
  > We don't care about response or failures 
  > it's just a trigger call (we'll auto retry anyway if it failed)
  -- jobName: queue name
  -- jobData: submitted with job
  -- jobTimeout: in seconds
  -- repeatPeriod: in seconds. Repeats job this many seconds *after* job completes.
###
guiltySpark = (jobName, jobData, jobTimeout, repeatPeriod) =>
  #Make atmosphere request
  console.log "[WAKE]", "Making request", jobName
  atmosphere.rainMaker.submit {type: jobName, name: jobName, data: jobData, timeout: jobTimeout}, (err, data) => #5min timeout
    if err?
      console.log "[ESUBMIT]", "Submission of #{jobName} failed.", err
    else  
      console.log "[JSUCCESS]", "Job #{jobName} completed.", data
      try
        #Log Report
        check(data).notNull().isUrl()          
        reports[jobName].url = data        
      catch e
        console.log "[WNODATA]", "Job #{jobName} did not return a valid report URL.", e
        return  
    #Recycle
    console.log "[SLEEP]", "#{jobName} resting for #{repeatPeriod} seconds."
    setTimeout () => 
      guiltySpark jobName, jobData, jobTimeout, repeatPeriod
    , repeatPeriod * 1000

_workerName = (fromID) ->
  nameBits = fromID.split("-")
  return "#{nameBits[0]}:#{nameBits[1][0...4]}"

_jobMessage = (message, headers, deliveryInfo) ->
  headers.task = JSON.parse(headers.task) if typeof headers.task is "string"
  if message?.level isnt "heartbeat"
    console.log "[RECEIVED]", JSON.stringify(message), JSON.stringify(headers)
  theMessage = {
    when: new Date()
    class: 
      type: headers.task.type
      name: headers.task.name
      step: headers.task.step
    msg: message
      # level: message.level
      # message: message.message
      # data: message.data
    }
  return theMessage

  

###
  Warning: HALO reference
  > Listen for and process incoming status messages from app servers executing DIS tasks
  Useful data formats and structures:
  -- message = {level: "start", message: message provided by job, data: data attached by job}
  -- headers.task = {type: , job:{name: , id:}, step: <optional>} -- job ticket
  -- deliveryInfo.queue = name of queue where delivered
###
cortana = (message, headers, deliveryInfo) =>

  
###
  Warning: HALO reference
  > Discover & clenanup dead workers
###
theChief = () ->
  now = new Date().getTime()
  for workerName, worker of workers
    if now - worker.alive > 4000
      delete workers[workerName] #dead worker!
  setTimeout () ->
    theChief()
  , 1000






########################################
## SCHEDULING
########################################

###
  Schedule new job
###
schedule = (snapshot) ->  
  rainDrop = undefined
  rainBucket = undefined
    
  #Transaction-protected Update Function
  updateFunction = (theItem) ->
    #--Update data
    rainDrop = theItem
    #TODO (jonathan) Sanity check this; delete if malformed; report error
    rainBucket = rainDrop?.job?.type
    
    #--Did we win the record lock?
    if theItem?
      return null #remove this job from the incoming rainDrops bucket
    else
      return undefined #abort (no changes)

  #On transaction complete
  onComplete = (error, committed, snapshot, dummy) ->
    console.log "\n\n\n=-=-=[onComplete]", committed, "\n\n\n" #xxx
    throw error if error?
    if committed
      console.log "[sky]", "IWIN", "Scheduling a #{rainBucket} job."
      #Move job to worker queue
      core.refs().rainCloudsRef.child("#{core.rainID()}/todo/#{rainBucket}/#{toProcess.name()}").set dataToProcess              
    else
      console.log "[sky]", "ILOSE", "Another broker beat me to the #{rainBucket} job. SHOULDN'T HAPPEN!"        
  
  #Begin Transaction
  snapshot.ref().transaction updateFunction, onComplete

###
  Determine which rainCloud (worker) should get the incoming rainDrop (job)
###
balance = (rainBucket, cbAssign) ->
  
  data.rainClouds









