uuid = require "node-uuid"
types = require "./types"
core = require "./core"
monitor = require "./monitor"

rainDrops = {} #indexed by "rainDropID" as "job.id"

exports._rainDrops = rainDrops

########################################
## SETUP
########################################

###
  rainDrops system initialization
  --role: String. 8 character (max) description of this rainMaker (example: "app", "eda", "worker", etc...)
###
exports.init = (role, url, token, cbDone) =>
  core.init role, url, token, (err) =>
    if err?
      cbDone err
      return    
    @start () ->
      cbDone undefined

###
  start internal machinery for job submission process
  -- Safe to call this function multiple times (subsequent calls ignored)
###
_started = false
exports.start = (cbStarted) =>
  if not _started
    console.log "[INIT]", core.rainID()
    foreman() #start job supervisor (runs asynchronously at 1sec intervals)    
    _started = true
  cbStarted()



########################################
## API
########################################

###
  Submit a job to the queue, but anticipate a response  
  -- jobChain: Either a single job, or an array of rainDrops
  --    job = {type: "typeOfJob/rainBucket", name: "jobName", data: {}, timeout: 30}
  -- cbJobDone: callback when response received (error, data) format
  --    if cbJobDone = undefined, no callback is issued or expected (no internal timeout, tracking, or callback)
          use for fire-and-forget dispatching
###
exports.submit = (jobChain, cbJobDone) ->
  #--Connection alive?
  if not core.ready() 
    error = console.log "[atmosphere]", "Not connected to #{core.urlLogSafe} yet!" 
    cbJobDone error if cbJobDone?
    return

  #--Format job chain
  if types.type(jobChain) isnt "array"
    jobChain = [jobChain]
  foundCB = false
  for eachJob, i in jobChain
    #--Assign ID
    eachJob.id = core.makeID eachJob.type, jobChain[0].name
    #--Clarify callback flow (only first callback=true remains)
    if foundCB or (not eachJob.callback?) or (not eachJob.callback) or (not cbJobDone?)
      eachJob.callback = false
    else
      foundCB = true if eachJob.callback? and eachJob.callback  
  jobChain[jobChain.length-1].callback = true if not foundCB and cbJobDone? #callback after last job if unspecified  
  
  #--Link jobs
  for eachJob, i in jobChain
    rainDrop = 
      job:
        name: jobChain[0].name
        type: eachJob.type
      data: eachJob.data
      log: 
        submit: core.log()
    if jobChain.length > 1 and i > 0
      rainDrop.prev = jobChain[i-1].id
    if jobChain.length > 1 and i < jobChain.length-1
      rainDrop.next = jobChain[i+1].id

    #--Callback processing
    if eachJob.callback is true  
      #--Inform Foreman Job Expected (default timeout to 1 min if unspecified)
      rainDrops[jobChain[i].id] = {type: jobChain[i].type, name: jobChain[0].name, timeout: jobChain[0].timeout ? 60, callback: cbJobDone}
      #--Listen for job completion callback
      console.log "\n\n\n=-=-=[maker.listenForCB]", eachJob, "\n\n\n" #xxx
      cbOnRainDropID = eachJob.id #save reference (async execution will corrupt eachJob otherwise)
      core.refs().rainDropsRef.child("#{cbOnRainDropID}/log").on "child_added", (snapshot) ->
        console.log "\n\n\n=-=-=[maker.submit.cb]", snapshot.name(), "\n\n\n" #xxx
        if snapshot.name() is "stop"
          core.refs().rainDropsRef.child(cbOnRainDropID).once "value", (snapshot) ->
            mailman snapshot.name(), snapshot.val()
    
    #--Submit /rainDrops
    console.log "\n\n\n=-=-=[chain Job #{i}]", jobChain[i], rainDrop, "\n\n\n" #xxx
    core.refs().rainDropsRef.child(jobChain[i].id).set rainDrop
  
  #--Mark chain ready for execution
  core.refs().skyRef.child("todo/#{jobChain[0].id}").set true
  

    
########################################
## INTERNAL OPERATIONS
########################################

###
  Assigns incoming messages to rainDrops awaiting a response
###
mailman = (rainDropID, rainDropVal) ->
  console.log "\n\n\n=-=-=[maker.mailman]", "Callback on job #{rainDropID}", rainDropVal, "\n\n\n" #xxx
  if not rainDrops["#{rainDropID}"]?
    console.log "[atmosphere]","WEXPIRED", "Received response for expired #{rainDropVal.job.type} job: #{rainDropID}."
    return    
  callback = rainDrops["#{rainDropID}"].callback #cache function pointer
  delete rainDrops["#{rainDropID}"] #mark job as completed
  setImmediate () -> #release stack frames/memory
    callback rainDropVal.result.errors, rainDropVal.result.response

###
  Implements timeouts for rainDrops-in-progress
###
foreman = () ->
  for jobID, jobMeta of rainDrops   
    console.log "\n\n\n=-=-=[foreman]", jobID, jobMeta.timeout, "\n\n\n" #xxx
    jobMeta.timeout = jobMeta.timeout - 1
    if jobMeta.timeout <= 0
      #cache -- necessary to prevent loss of function pointer
      callback = jobMeta.callback 
      job = jobMeta

      #mark job as completed
      delete rainDrops[jobID] #mark job as completed
      
      #release stack frames/memory
      process.nextTick () -> 
        callback console.log "jobTimeout", "A response to job #{job.type}-#{job.name} was not received in time."
  setTimeout(foreman, 1000)
