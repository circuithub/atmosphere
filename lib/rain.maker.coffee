{isArray} = require "lodash"
nconf = require "nconf"
elma  = require("elma")(nconf)
uuid = require "node-uuid"
types = require "./types"
core = require "./core"
monitor = require "./monitor"

module.exports = ->
  jobs = {} #indexed by "headers.job.id"
  makerRoleID = undefined
  api = {}
  api._jobs = jobs

  ########################################
  ## SETUP
  ########################################

  ###
    Jobs system initialization
    --role: String. 8 character (max) description of this rainMaker (example: "app", "eda", "worker", etc...)
  ###  
  api.init = (role, cbDone) ->
    #core.setRole(role)
    if makerRoleID?
      throw "Rain maker has already been initialized"
    makerRoleID = core.generateRoleID role
    core.connect (err) ->
      if err?
        cbDone err
        return    
      api.start () ->
        monitor.boot()
        cbDone undefined

  api.getRoleID = -> makerRoleID

  api.start = (cbStarted) ->
    console.log "[INIT]", core.rainID(makerRoleID)
    foreman() #start job supervisor (runs asynchronously at 1sec intervals)
    api.listen core.rainID(makerRoleID), mailman, cbStarted

  ########################################
  ## API
  ########################################

  ###
    Submit a job to the queue, but anticipate a response  
    -- jobChain: Either a single job, or an array of jobs
    --    job = {type: "typeOfJob/queueName", name: "jobName", data: {}, timeout: 30}
  ###
  api.submit = (jobChain, cbSubmitted) ->
    if not core.ready() 
      error = elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
      cbSubmitted error
      return
    if not isArray jobChain
      jobChain = [jobChain]
    for job in jobChain when job.callback
      elma.warning "callback deprecated", "callback on jobs are no longer supported"
    # jobChain[jobChain.length-1].callback = true if not foundCB #callback after last job if unspecified
    #--Look at first job
    job = jobChain.shift()

    #[2.] Inform Foreman Job Expected
    job.timeout ?= 60
    job.id = uuid.v4()
    if jobs[job.id]?
      error = elma.error "jobAlreadyExistsError", "Job #{jobs[job.id].type}-#{jobs[job.id].name} Already Pending"
      cbSubmitted error
      return
    
    #[3.] Submit Job
    payload = 
      data: job.data ?= {}
      next: jobChain
    headers =
      callback: job.callback ? false
      job: 
        name: job.name
        id:   job.id
      returnQueue: core.rainID makerRoleID
    core.submit job.type, payload, headers
    cbSubmitted()

  ###
    Subscribe to incoming jobs in the queue (exclusively -- block others from listening)
    >> Used for private response queues (responses to submitted jobs)
    -- type: type of jobs to listen for (name of job queue)
    -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
    -- cbListening: callback after listening to queue has started --> function (err) 
  ###
  api.listen = (type, cbExecute, cbListening) ->
    core.listen type, cbExecute, true, false, false, cbListening

  ###
    The number of active jobs (submitted, but not timed-out or returned yet)
  ###
  api.count = () ->
    return Object.keys(jobs).length

  ###
    Create the externally visible job key 
    -- Job chains must have unique external keys, even though this isn't enforced at present
  ###
  api.jobName = core.jobName


  ########################################
  ## INTERNAL OPERATIONS
  ########################################

  ###
    Assigns incoming messages to jobs awaiting a response
  ###
  mailman = (message, headers, deliveryInfo) ->
    if not jobs["#{headers.job.id}"]?
      elma.warning "expiredJobError", "Received response for expired job #{headers.type}-#{headers.job.name} #{headers.job.id}."
      return    
    callback = jobs["#{headers.job.id}"].callback #cache function pointer
    delete jobs["#{headers.job.id}"] #mark job as completed
    process.nextTick () -> #release stack frames/memory
      callback message.errors, message.data

  ###
    Implements timeouts for jobs-in-progress
  ###
  foreman = () ->
    for jobID, jobMeta of jobs
      jobMeta.timeout = jobMeta.timeout - 1
      if jobMeta.timeout <= 0
        #cache -- necessary to prevent loss of function pointer
        callback = jobMeta.callback 
        job = jobMeta

        #mark job as completed
        delete jobs[jobID] #mark job as completed
        
        #release stack frames/memory
        process.nextTick () -> 
          callback elma.error "jobTimeout", "A response to job #{job.type}-#{job.name} was not received in time."
    setTimeout(foreman, 1000)

  return api
