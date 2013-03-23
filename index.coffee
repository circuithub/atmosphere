amqp = require "amqp"
nconf = require "nconf"
elma  = require("elma")(nconf)
uuid = require "node-uuid"
bsync = require "bsync"
domain = require "domain"

url = nconf.get("CLOUDAMQP_URL") or "amqp://brkoacph:UNIBQBLE1E-_t-6fFapavZaMN68sdRVU@tiger.cloudamqp.com/brkoacph" # default to circuithub-staging
urlLogSafe = url.substring url.indexOf("@") #Safe to log this value (strip password out of url)
conn = undefined
connectionReady = false

queues = {}
listeners = {}
jobs = {}
jobWorkers = {}

rainID = uuid.v4()
rainCloudID = nconf.get("CLOUD_ID")
rainCloudID ?= uuid.v4()

currentJob = {}

#Set ENV var CLOUD_ID on atmosphere.raincloud servers

###
1. worker functions in rain cloud apps get called like this:
  your_function(ticket, jobData)
2. When done, call thunder and give the ticket back along with any response data (must serialize to JSON)...
  atmosphere.thunder ticket, responseData
###

########################################
## SETUP / INITIALIZATION
########################################

###
  Jobs system initialization
###
rainMaker = (cbDone) =>
  console.log "\n\n\n=-=-=[init.rainMaker](1)", "\n\n\n" #xxx  
  @_connect (err) =>
    console.log "\n\n\n=-=-=[init.rainMaker](2)", err, "\n\n\n" #xxx  
    if err?
      cbDone err
      return
    foreman() #start job supervisor (runs asynchronously at 1sec intervals)
    @listenFor rainID, mailman, cbDone 

###
  jobTypes -- object with jobType values and worker function callbacks as keys; { jobType1: cbDoJobType1, jobType2: .. }
  -- Safe to call this function multiple times. It adds additional job types. If exists, jobType is ignored during update.
###
rainCloud = (jobTypes, cbDone) =>
  console.log "\n\n\n=-=-=[init.rainCloud](1)", "\n\n\n" #xxx  
  #[1.] Connect to message server
  @_connect (err) =>
    if err?
      cbDone err
      return
    #[2.] Publish all jobs we can handle (listen to all queues for these jobs)
    workerFunctions = []    
    for jobType of jobTypes
      if not jobWorkers[jobType]?
        jobWorkers[jobType] = jobTypes[jobType]
        workerFunctions.push bsync.apply @listenTo, jobType, lightning
    console.log "\n\n\n=-=-=[init.rainCloud](2)", jobWorkers, "\n\n\n" #xxx  
    bsync.parallel workerFunctions, (allErrors, allResults) =>
      if allErrors?
        cbDone allErrors
        return
      cbDone()

exports.init = {rainMaker: rainMaker, rainCloud: rainCloud}

###
  Report whether the Job queueing system is ready for use (connected to RabbitMQ backing)
###
exports.ready = () ->
  return connectionReady

###
  Connect to specified RabbitMQ server, callback when done.
  -- This is done automatically at the first module loading
  -- However, this method is exposed in case, you want to explicitly wait it out and confirm valid connection in app start-up sequence
  -- Connection is enforced, so if connection doesn't exist, nothing else will work.
###
exports._connect = (cbConnected) ->
  if not conn?
    elma.info "rabbitConnecting", "Connecting to RabbitMQ..."
    conn = amqp.createConnection {heartbeat: 10, url: url} # create the connection
    conn.on "error", (err) ->
      elma.error "rabbitConnectedError", "RabbitMQ server at #{urlLogSafe} reports ERROR.", err
    conn.on "ready", (err) ->
      elma.info "rabbitConnected", "Connected to RabbitMQ!"
      if err?
        elma.error "rabbitConnectError", "Connection to RabbitMQ server at #{urlLogSafe} FAILED.", err
        cbConnected err
        return
      connectionReady = true
      cbConnected undefined
  else
    cbConnected undefined


########################################
## RAINMAKER JOBS (submit jobs)
########################################

###
  Assigns incoming messages to jobs awaiting a response
###
mailman = (message, headers, deliveryInfo) ->
  if not jobs["#{headers.type}-#{headers.job}"]?
    elma.warning "noSuchJobError","Message received for job #{deliveryInfo.queue}-#{headers.job}, but job doesn't exist."
    return  
  if not jobs["#{headers.type}-#{headers.job}"].id is headers.job.id
    elma.warning "expiredJobError", "Received response for expired job #{deliveryInfo.queue}-#{headers.job} #{headers.job.id}."
    return

  console.log "\n\n\n=-=-=[mailman]", "#{headers.type}-#{headers.job}", "\n\n\n" #xxx
    
  jobs["#{headers.type}-#{headers.job}"].cb undefined, message
  delete jobs["#{headers.type}-#{headers.job}"]

###
  Implements timeouts for jobs-in-progress
###
foreman = () ->
  for job of jobs    
    jobs[job].timeout = jobs[job].timeout - 1
    if jobs[job].timeout <= 0
      jobs[job].cb elma.error "jobTimeout", "A response to job #{job} was not received in time."
      delete jobs[job]
  setTimeout(foreman, 1000)

###
  Submit a job to the queue, but anticipate a response
  -- type: type of job (name of job queue)
  -- job: must be in this format {name: "jobName", data: {}, timeout: 30 } the job details (message body) <-- timeout (in seconds) is optional defaults to 30 seconds
  -- cbJobDone: callback when response received (error, data) format
###
exports.submitFor = (type, job, cbJobDone) =>
  if not connectionReady 
    cbJobDone elma.error "noRabbitError", "Not connected to #{urlLogSafe} yet!" 
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
  conn.publish type, JSON.stringify(job.data), {
                            contentType: "application/json", 
                            headers: {
                              job: {name: job.name, id: job.id}
                              returnQueue: rainID
                            }
                          }

###
  Subscribe to incoming jobs in the queue (exclusively -- block others from listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listenFor = (type, cbExecute, cbListening) =>
  _listen type, cbExecute, true, false, false, cbListening



########################################
## CLOUD JOBS (receive and do jobs)
########################################

###
  Receives work to do messages on cloud and dispatches
  Messages are dispatched to the callback function this way:
    function(ticket, data) ->
###
lightning = (message, headers, deliveryInfo) =>
  if currentJob[deliveryInfo.queue]?
    #PANIC! BAD STATE! We got a new job, but haven't completed previous job yet!
    elma.error "duplicateJobAssigned", "Two jobs were assigned to atmosphere.cloud server at once! SHOULD NOT HAPPEN.", currentJob, deliveryInfo, headers, message
    return
  currentJob[deliveryInfo.queue] = {
    type: deliveryInfo.queue
    name: headers.job.name
    id: headers.job.id
    data: message
    returnQueue: headers.returnQueue
  }
  console.log "\n\n\n=-=-=[lightning]", deliveryInfo.queue, jobWorkers, headers.job, currentJob.data, "\n\n\n" #xxx  
  jobWorkers[deliveryInfo.queue]({type: deliveryInfo.queue, job: headers.job}, currentJob.data)

###
  Reports completed job on a Rain Cloud
  -- data: the job response data (message body)
###
exports.doneWith = (ticket, message) =>
  if not connectionReady 
    #TODO: HANDLE THIS BETTER
    elma.error "noRabbitError", "Not connected to #{urlLogSafe} yet!" 
    return
  if not currentJob[ticket.type]?
    #TODO: HANDLE THIS BETTER
    elma.error "noTicketWaiting", "Ticket for #{ticket.type} has no current job pending!" 
    return
  header = {job: currentJob[ticket.type].job, type: currentJob[ticket.type].type, rainCloudID: rainCloudID}
  console.log "\n\n\n=-=-=[thunder](1)", header, "\n\n\n" #xxx  
  p = conn.publish currentJob[ticket.type].returnQueue, JSON.stringify(message), {contentType: "application/json", headers: header} 
  console.log "\n\n\n=-=-=[thunder](2)", p, "\n\n\n" #xxx  
  @acknowledge currentJob[ticket.type].type, (err) ->
    if err?
      #TODO: HANDLE THIS BETTER
      elma.error "cantAckError", "Could not send ACK", currentJob[ticket.type], err 
      return
    currentJob[ticket.type] = undefined #done with current job, update state
    console.log "\n\n\n=-=-=[thunder](3)", ticket.type, "\n\n\n" #xxx  

###
  Acknowledge the last job received of the specified type
  -- type: type of job you are ack'ing (you get only 1 job of any type at a time, but can subscribe to multiple types)
  -- cbAcknowledged: callback after ack is sent successfully
###
exports.acknowledge = (type, cbAcknowledged) =>
  if not connectionReady 
    cbAcknowledged elma.error "noRabbitError", "Not connected to #{urlLogSafe} yet!" 
    return
  if not queues[type]?
    cbAcknowledged "Connection to queue for job type #{type} not available! Are you listening to this queue?"
    return
  queues[type].shift()
  cbAcknowledged undefined

###
  Subscribe to persistent incoming jobs in the queue (non-exclusively)
  (Queue will continue to exist even if no-one is listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err)  
###
exports.listenTo = (type, cbExecute, cbListening) =>
  console.log "\n\n\n=-=-=[listenTo]", type, "\n\n\n" #xxx  
  _listen type, cbExecute, false, true, true, cbListening
  



########################################
## INTERNAL / UTILITY
########################################

###
  Force delete of a queue (for maintainence/dev future use)
###
_delete = () =>
  #Unsubscribe any active listener
  if queues[typeResponse]?  
    #Delete Queue
    queues[typeResponse].destroy {ifEmpty: false, ifUnused: false}
    #Update global state
    queues[typeResponse] = undefined
    listeners[typeResponse] = undefined
    cbDone undefined
  else
    cbDone "Not currently aware of #{typeResponse}! You can't blind delete."

###
  Subscribe to incoming jobs in the queue (non-exclusively)
  (Queue dies if no one listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listen = (type, cbExecute, cbListening) =>
  _listen type, cbExecute, false, false, true, cbListening

###
  Implements listening behavior.
  -- Prevents subscribing to a queue multiple times
  -- Records the consumer-tag so you can unsubscribe
###
_listen = (type, cbExecute, exclusive, persist, useAcks, cbListening) =>
  if not connectionReady 
    cbListening elma.error "noRabbitError", "Not connected to #{urlLogSafe} yet!" 
    return
  if not queues[type]?
    queue = conn.queue type, {autoDelete: not persist}, () -> # create a queue (if not exist, sanity check otherwise)
      #save reference so we can send acknowledgements to this queue
      queues[type] = queue 
      # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
      subscribeDomain = domain.create()
      subscribeDomain.on "error", (err) -> 
        cbListening err
      subscribeDomain.run () ->
        queue.subscribe({ack: useAcks, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag)
      cbListening undefined
  else
    if not listeners[type]? #already listening?
      queue.subscribe({ack: useAcks, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag) # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
    cbListening undefined