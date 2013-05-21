nconf = require "nconf"
elma  = require("elma")(nconf)
uuid = require "node-uuid"
types = require "./types"
core = require "./core"
monitor = require "./monitor"

jobs = {} #indexed by "#{headers.type}-#{headers.job.name}"
callbacks = {} #indexed by job.id



########################################
## SETUP
########################################

###
  Jobs system initialization
  --role: String. 8 character (max) description of this rainMaker (example: "app", "eda", "worker", etc...)
###
exports.init = (role, cbDone) ->
  core.setRole(role)
  core.connect (err) ->
    if err?
      cbDone err
      return
    foreman() #start job supervisor (runs asynchronously at 1sec intervals)
    exports.listen core.rainID(), mailman, cbDone 
    monitor.boot()



########################################
## API
########################################

###
  Submit a job to the queue, but anticipate a response  
  -- jobChain: Either a single job, or an array of jobs
  --    job = {type: "typeOfJob/queueName", name: "jobName", data: {}, timeout: 30}
  -- cbJobDone: callback when response received (error, data) format
###
exports.submit =   
  (jobChain, cbJobDone) ->
    if not core.ready() 
      cbJobDone elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
      return

    #[1.] Array Prep (job chaining)
    #--Format
    if types.type jobChain isnt "array"
      jobChain = [jobChain]
    #--Clarify callback flow (only first callback=true remains)
    foundCB = false
    for eachJob in jobChain
      if foundCB or (not eachJob.callback?) or (not eachJob.callback)
        eachJob.callback = false
      else
        foundCB = true if eachJob.callback? and eachJob.callback   
    jobChain[jobChain.length-1].callback = true if not foundCB #callback after last job if unspecified
    #--Look at first job
    job = jobChain.shift()
    console.log "\n\n\n=-=-=[maker.submit]", job, "\n\n\n" #xxx

    #[2.] Inform Foreman Job Expected
    if jobs["#{job.type}-#{job.name}"]?
      cbJobDone elma.error "jobAlreadyExistsError", "Job #{job.type}-#{job.name} Already Pending"
      return
    job.timeout ?= 60
    job.id = uuid.v4()
    jobs["#{job.type}-#{job.name}"] = {id: job.id, timeout: job.timeout}
    callbacks[job.id] = cbJobDone
    
    #[3.] Submit Job
    payload = {data: job.data ?= {}, next: jobChain}
    core.submit job.type, payload, {
                                callback: job.callback
                                job: {name: job.name, id: job.id}
                                returnQueue: core.rainID()
                            }

###
  Subscribe to incoming jobs in the queue (exclusively -- block others from listening)
  >> Used for private response queues (responses to submitted jobs)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listen = (type, cbExecute, cbListening) =>
  core.listen type, cbExecute, true, false, false, cbListening

###
  The number of active jobs (submitted, but not timed-out or returned yet)
###
exports.count = () ->
  return Object.keys(jobs).length



########################################
## INTERNAL OPERATIONS
########################################

###
  Assigns incoming messages to jobs awaiting a response
###
mailman = (message, headers, deliveryInfo) ->
  if not callbacks["#{headers.job.id}"]?
    elma.warning "expiredJobError", "Received response for expired job #{headers.type}-#{headers.job.name} #{headers.job.id}."
    return    
  callback = callbacks["#{headers.job.id}"] #cache function pointer
  delete jobs["#{headers.type}-#{headers.job.name}"] #mark job as completed
  delete callbacks["#{headers.job.id}"] #mark job as completed
  process.nextTick () -> #release stack frames/memory
    callback message.errors, message.data

###
  Implements timeouts for jobs-in-progress
###
foreman = () ->
  for job of jobs then do (job) ->    
    jobs[job].timeout = jobs[job].timeout - 1
    if jobs[job].timeout <= 0
      callback = jobs[job].cb #necessary to prevent loss of function pointer
      delete jobs[job] #mark job as completed
      process.nextTick () -> #release stack frames/memory
        callback elma.error "jobTimeout", "A response to job #{job} was not received in time."
  setTimeout(foreman, 1000)
