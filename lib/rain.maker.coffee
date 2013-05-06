nconf = require "nconf"
elma  = require("elma")(nconf)
uuid = require "node-uuid"

core = require "./core"
monitor = require "./monitor"

jobs = {}



########################################
## SETUP
########################################

###
  Jobs system initialization
  --role: String. 8 character (max) description of this rainMaker (example: "app", "eda", "worker", etc...)
###
exports.init = (role, cbDone) =>
  core.setRole(role)
  core.connect (err) =>
    if err?
      cbDone err
      return
    foreman() #start job supervisor (runs asynchronously at 1sec intervals)
    @listen core.rainID, mailman, cbDone 
    monitor.boot()



########################################
## API
########################################

###
  Submit a job to the queue, but anticipate a response
  -- type: type of job (name of job queue)
  -- job: must be in this format {name: "jobName", data: {}, timeout: 30 } the job details (message body) <-- timeout (in seconds) is optional defaults to 30 seconds
  -- cbJobDone: callback when response received (error, data) format
###
exports.submit = (type, job, cbJobDone) =>
  if not core.ready() 
    cbJobDone elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
    return
  #[1.] Inform Foreman Job Expected
  if jobs["#{type}-#{job.name}"]?
    cbJobDone elma.error "jobAlreadyExistsError", "Job #{type}-#{job.name} Already Pending"
    return
  job.timeout ?= 60
  job.id = uuid.v4()
  jobs["#{type}-#{job.name}"] = {id: job.id, cb: cbJobDone, timeout: job.timeout}
  #[2.] Submit Job
  job.data ?= {} #default value if unspecified
  core.publish type, job.data, {
                              job: {name: job.name, id: job.id}
                              returnQueue: rainID
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
  if not jobs["#{headers.type}-#{headers.job.name}"]?
    elma.warning "noSuchJobError","Message received for job #{headers.type}-#{headers.job.name}, but job doesn't exist."
    return  
  if not jobs["#{headers.type}-#{headers.job.name}"].id is headers.job.id
    elma.warning "expiredJobError", "Received response for expired job #{headers.type}-#{headers.job.name} #{headers.job.id}."
    return    
  callback = jobs["#{headers.type}-#{headers.job.name}"].cb #cache function pointer
  delete jobs["#{headers.type}-#{headers.job.name}"] #mark job as completed
  process.nextTick () -> #release stack frames/memory
    callback message.errors, message.data

###
  Implements timeouts for jobs-in-progress
###
foreman = () ->
  for job of jobs    
    jobs[job].timeout = jobs[job].timeout - 1
    if jobs[job].timeout <= 0
      callback = jobs[job].cb #necessary to prevent loss of function pointer
      delete jobs[job] #mark job as completed
      process.nextTick () -> #release stack frames/memory
        callback elma.error "jobTimeout", "A response to job #{job} was not received in time."
  setTimeout(foreman, 1000)
