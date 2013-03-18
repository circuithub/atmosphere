amqp = require "amqp"
nconf = require "nconf"
elma  = require("elma")(nconf)
domain = require "domain"
uuid = require "node-uuid"

url = nconf.get("CLOUDAMQP_URL") or "amqp://brkoacph:UNIBQBLE1E-_t-6fFapavZaMN68sdRVU@tiger.cloudamqp.com/brkoacph" # default to circuithub-staging
conn = undefined
connectionReady = false

queues = {}
listeners = {}
jobs = {}
rainID = uuid.v4()

###
  Assigns incoming messages to jobs awaiting a response
###
mailman = (message, headers, deliveryInfo) ->
  if not jobs[headers.job]?
    elma.warning "Message received for job #{}, but job doesn't exist."
    return
  jobs[headers.job].data = message

foreman = () ->
  toDelete = []
  for job of jobs
    if jobs[job].data?
      toDelete.push job
      jobs[job].cb(undefined, jobs[job].data)
  for job in toDelete
    jobs[job] = undefined

###
  Submit a job to the queue, but anticipate a response
  -- type: type of job (name of job queue)
  -- type: type of the job's response (name of the response queue)
  -- job: must be in this format {name: "jobName", data: {} } the job details (message body)
  -- cbResponse: callback when response received
  -- cbSubmitted: callback when submition complete
###
exports.submitFor = (type, job, cbJobDone) =>
  if not connectionReady 
    cbJobDone "Not connected to #{url} yet!" 
    return
  #[1.] Inform Foreman Job Expected
  if jobs[job.name]?
    cbJobDone "Job Already Pending"
    return
  jobs[job.name] = {cb: cbJobDone}
  #[2.] Submit Job
  conn.publish type, job, {
                            contentType: "application/json", 
                            headers: {
                              job: job.name, 
                              returnQueue: rainID
                            }
                          }
  #[2.] Wait for Response
  process.nextTick()

rainmaker = (cbDone) =>
  @connect (err) =>
    if err?
      cbDone err
      return
    @listenFor rainID, mailman, cbDone 

cloud = (cbDone) =>
  @connect cbDone # Up to dev to listenTo work queues that this cloud can handle

exports.init = {rainmaker: rainmaker, cloud: cloud}

########################################
## SETUP / INITIALIZATION
########################################

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
exports.connect = (cbConnected) ->
  elma.info "Connecting to RabbitMQ..."
  conn = amqp.createConnection {heartbeat: 10, url: url} # create the connection
  conn.on "error", (err) ->
    console.log "\n\n===here be errors!==="
  conn.on "ready", (err) ->
    elma.info "Connected to RabbitMQ!"
    if err?
      elma.error "Connection to RabbitMQ server at #{url} FAILED.", err
      cbConnected err
      return
    connectionReady = true
    cbConnected undefined




########################################
## LOW-LEVEL API (actions w/o response)
########################################

###
  Submit a job to the queue 
  (if the queue doesn't exist the job is lost silently)
  (Note: Synchronous Function)
  -- type: type of job (name of job queue)
  -- data: the job details (message body)
###
exports.submit = (type, data) =>
  if not connectionReady 
    cbSubmitted "Connection to #{url} not ready yet!" 
    return
  job = {
          typeResponse: undefined
          data: JSON.stringify(data)
        }
  conn.publish type, job, {contentType: "application/json", headers:{job: "job name", returnQueue: "testing1234"}} 

###
  Subscribe to incoming jobs in the queue (non-exclusively)
  (Queue dies if no one listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listen = (type, cbExecute, cbListening) =>
  _listen type, cbExecute, false, true, cbListening

###
  Subscribe to persistent incoming jobs in the queue (non-exclusively)
  (Queue will continue to exist even if no-one is listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err)  
###
exports.listenTo = (type, cbExecute, cbListening) =>
  _listen type, cbExecute, false, false, cbListening

###
  Acknowledge the last job received of the specified type
  -- type: type of job you are ack'ing (you get only 1 job of any type at a time, but can subscribe to multiple types)
  -- cbAcknowledged: callback after ack is sent successfully
###
exports.acknowledge = (type, cbAcknowledged) =>
  if not connectionReady 
    cbAcknowledged "Connection to #{url} not ready yet!" 
    return
  if not queues[type]?
    cbAcknowledged "Connection to queue for job type #{type} not available! Are you listening to this queue?"
    return
  queues[type].shift()
  cbAcknowledged undefined



########################################
## JOBS API (anticipating a response)
########################################



###
  Subscribe to incoming jobs in the queue (exclusively -- block others from listening)
  -- type: type of jobs to listen for (name of job queue)
  -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
  -- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listenFor = (type, cbExecute, cbListening) =>
  _listen type, cbExecute, true, true, cbListening

exports.ignore = (type, cbDone) =>
  

###
  Stop listening for jobs of the specified job response type
###
exports.doneWith = (typeResponse, cbDone) =>
  console.log "\n\n\n=-=-=[doneWith]", listeners, "\n\n\n" #xxx 
  if queues[typeResponse]?  
    if listeners[typeResponse]?
      queues[typeResponse].unsubscribe(listeners[typeResponse]).addCallback (ok) ->
        console.log "\n\n\n=-=-=[doneWith](2)", ok      
        #Update global state      
        queues[typeResponse] = undefined #auto-delete will kill this exclusive queue on unsubscribe
        listeners[typeResponse] = undefined
        cbDone undefined
    else
      cbDone "Not currently subscribed to #{typeResponse}!"
  else
    cbDone "Not currently aware of #{typeResponse} so there is no way you are subscribed."



########################################
## INTERNAL / UTILITY
########################################

###
  Force delete of a queue
###
_delete = () =>
  console.log "\n\n\n=-=-=[doneWith]", listeners, "\n\n\n" #xxx 
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
  Implements listening behavior.
  -- Prevents subscribing to a queue multiple times
  -- Records the consumer-tag so you can unsubscribe
###
_listen = (type, cbExecute, exclusive, persist, cbListening) =>
  if not connectionReady 
    cbListening "Connection to #{url} not ready yet!" 
    return
  if not queues[type]?
    queue = conn.queue type, {autoDelete: persist}, () -> # create a queue (if not exist, sanity check otherwise)
      #save reference so we can send acknowledgements to this queue
      queues[type] = queue 
      # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
      subscribeDomain = domain.create()
      subscribeDomain.on "error", (err) -> 
        console.log "\n\n\n---domainError:", err
        cbListening err
      subscribeDomain.run () ->
        queue.subscribe({ack: true, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag)
      cbListening undefined
  else
    if not listeners[type]? #already listening?
      queue.subscribe({ack: true, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag) # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
    cbListening undefined