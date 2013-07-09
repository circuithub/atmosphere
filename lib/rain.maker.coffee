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
    core.refs().rainMakersRef.child("#{core.rainID()}/stats/alive").set true #TODO: unified heartbeating
    @start () ->
      monitor.boot()
      cbDone undefined

exports.start = (cbStarted) =>
  console.log "[INIT]", core.rainID()
  foreman() #start job supervisor (runs asynchronously at 1sec intervals)
  @listen()
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
    if not core.ready() 
      error = console.log "[atmosphere]", "Not connected to #{core.urlLogSafe} yet!" 
      cbJobDone error if cbJobDone?
      return

    #[1.] Array Prep (job chaining)
    #--Format
    if types.type(jobChain) isnt "array"
      jobChain = [jobChain]
    #--Clarify callback flow (only first callback=true remains)
    foundCB = false
    for eachJob in jobChain
      if foundCB or (not eachJob.callback?) or (not eachJob.callback) or (not cbJobDone?)
        eachJob.callback = false
      else
        foundCB = true if eachJob.callback? and eachJob.callback  
    jobChain[jobChain.length-1].callback = true if not foundCB and cbJobDone? #callback after last job if unspecified
    #--Look at first job
    job = jobChain.shift()

    #[2.] Submit Job
    payload = 
      data: job.data ?= {}
      next: jobChain
    headers =
      callback: job.callback
      job: 
        name: job.name
        type: job.type
      returnQueue: core.rainID()
    rainDropID = core.submit job.type, payload, headers

    #[3.] Inform Foreman Job Expected
    job.timeout ?= 60
    job.id = rainDropID
    #If callback is desired listen for it
    if cbJobDone? 
      rainDrops[job.id] = {type: job.type, name: job.name, timeout: job.timeout, callback: cbJobDone}    
    
###
  Subscribe to incoming rainDrops in the queue 
  -- This is how callbacks get effected
###
exports.listen = () =>
  core.refs().rainMakersRef.child("#{core.rainID()}/done/").on "child_added", (snapshot) ->
    rainDropID = snapshot.name()
    rainDrop = snapshot.val()
    core.refs().rainMakersRef.child("#{core.rainID()}/done/#{rainDropID}").remove()
    mailman rainDrop.job.type, rainDropID, rainDrop

###
  The number of active rainDrops (submitted, but not timed-out or returned yet)
###
exports.count = () ->
  return Object.keys(rainDrops).length



########################################
## INTERNAL OPERATIONS
########################################

###
  Assigns incoming messages to rainDrops awaiting a response
###
mailman = (rainBucket, rainDropID, rainDrop) ->
  if not rainDrops["#{rainDropID}"]?
    console.log "[atmosphere]","WEXPIRED", "Received response for expired #{rainBucket} job: #{rainDropID}."
    return    
  callback = rainDrops["#{rainDropID}"].callback #cache function pointer
  delete rainDrops["#{rainDropID}"] #mark job as completed
  process.nextTick () -> #release stack frames/memory
    callback rainDrop.response.errors, rainDrop.response.data

###
  Implements timeouts for rainDrops-in-progress
###
foreman = () ->
  for jobID, jobMeta of rainDrops   
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
