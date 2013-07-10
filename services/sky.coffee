_          = require "underscore"
atmosphere = require "../index"
disTasks   = require "dis-task-list"
{check}    = require "validator"
nconf      = require "nconf"

stats    = {}
messages = []
reports  = {}
workers  = {}

###
  Initialize a new worker data record
###
_createWorker = (fromID) ->
  workers[fromID] =
    alive: new Date().getTime() #heartbeat
    name: _workerName fromID
    cpu: [0,0,0] #cpu load averages over last [1min, 5min, 15min]
    mem:
      rss: 0 #total node.exe memory allocation
      heapPercent: 0 #(derived)
      heapUsed: 0 #head used
      heapTotal: 0 #total allocated heap
    stats:
      running: 0 #number of currently running jobs
      complete: 0 #number of jobs completed
      uptime: 0 #number of minutes of continuous uptime
      idleTime: 0 #number of idle milliseconds (time after/between jobs)
    jobs: {} #Initialization -- see following for format
      ###
      jobName1: 
        when: new Date()
        class: 
          type: headers.task.type
          name: headers.task.job.name
          step: headers.task.step
        msg:
          level: message.level
          message: message.message
          data: message.data
        progress:
          completed:
          inTotal:
          withData:
          withErrors:
          percent: (derived)
      jobName2: 
        ...
      ###



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
  #Format Message
  theJob = _jobMessage message, headers, deliveryInfo

  #Update Receive Statistics
  stats[message.level] ?= 0
  stats[message.level]++
  
  #Most Recently Received Messages
  if theJob.msg.level isnt "heartbeat" #exclude heartbeats from message log to avoid clutter
    messages.push theJob    
    messages.shift() if messages.length > 25
  
  #Worker Basics
  if not workers[headers.fromID]?
    _createWorker headers.fromID
  else
    workers[headers.fromID].alive = new Date().getTime() #WDT

  #Current Worker Status
  jobs = workers[headers.fromID].jobs
  switch theJob.msg.level
    when "heartbeat"
      workers[headers.fromID][k] = v for k, v of theJob.msg.data
      workers[headers.fromID].name = headers.fromName if headers.fromName?.length > 0
      data = workers[headers.fromID]
      #memory
      data.mem.rss = (data.mem.rss/1e6).toFixed(3)
      data.mem.heapPercent = (theJob.msg.data.mem.heapUsed / theJob.msg.data.mem.heapTotal * 100).toFixed(2)
      data.mem.heapUsed = (data.mem.heapUsed/1e6).toFixed(3)
      data.mem.heapTotal = (data.mem.heapTotal/1e6).toFixed(3)
      #update knowledge of currently running jobs
      if theJob.msg.data?.currentJobs?
        data.stats.running = theJob.msg.data.currentJobs.length        
        data.jobs = _.pick data.jobs, theJob.msg.data.currentJobs #Synchronize (remove dead jobs)
      else
        data.stats.running = 0
        data.jobs = {} #reset (no jobs running)
      #save update
      workers[headers.fromID] = data
    when "progress"
      jobs[headers.task.type] = theJob
      jobs[headers.task.type].progress = theJob.msg.data
      jobs[headers.task.type].progress.percent = (theJob.msg.data.completed/theJob.msg.data.inTotal*100).toFixed(2)
    else
      priorProgress = jobs[headers.task.type].progress if jobs[headers.task.type]?
      priorProgress ?= {completed:0, inTotal:1, percent: 0}
      jobs[headers.task.type] = theJob
      jobs[headers.task.type].progress = priorProgress

  #Report Filing
  reports[headers.task.type] = theJob if theJob.msg.level is "report"

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

exports.dashboard = () =>
  dashboard = 
    stats: stats
    messages: messages
    reports: reports
    workers: workers
  return dashboard

exports.stats = () =>
  return stats



exports.init = (cbReady) =>
  atmosphere.rainMaker.init "spark", nconf.get("FIREBASE_URL"), nconf.get("FIREBASE_SECRET"), (err) ->
    #[1.] Connect
    if err?
      console.log "[ECONNECT]", "Could not connect to atmosphere.", err
      cbReady err
      return
    #[2.] Load tasks
    for task of disTasks
      if disTasks[task].type is "dis"
        if disTasks[task].period > 0
          console.log "[init] Will EXECUTE #{task}", JSON.stringify disTasks[task]
          guiltySpark task, disTasks[task].data, disTasks[task].timeout, disTasks[task].period
        else
          console.log "[init] IGNORING #{task} (no period specified)"
    #[3.] Listen for responses
    #atmosphere.rainBucket.listen "disResponse", cortana, cbReady
    #[4.] Monitor for dead workers
    theChief()
