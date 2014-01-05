amqp = require "amqp"
_ = require "underscore"
_s = require "underscore.string"
elma  = require("elma")(require "nconf")
uuid = require "node-uuid"
bsync = require "bsync"
domain = require "domain"
types = require "./types"

# See lodash-ext.coffee for deferUntil implementation
deferUntil = (condFn, fn, args...) ->
  if condFn()
    fn args...
  else
    _.defer -> deferUntil condFn, fn, args...

########################################
## STATE MANAGEMENT
########################################

amqpUrl = undefined
conn = undefined
connectionReady = false

queues = {}
listeners = {}



########################################
## IDENTIFICATION
########################################

_rainID = uuid.v4() #Unique ID of this process/machine
# _roleID = undefined
# exports.rainID = () ->
#   return if _roleID? then _roleID else _rainID
exports.rainID = (roleID=null) ->
  if roleID? then "#{roleID}-#{_rainID}" else _rainID

###
  Format machine prefix
###
exports.generateRoleID = (role) ->
  _roleID = _s.humanize role
  _roleID = _roleID.replace " ", "_"
  _roleID = _s.truncate _roleID, 8
  _roleID = _s.truncate _roleID, 7 if _roleID[7] is "_"
  # _roleID = _roleID + "-" + _rainID
  return _roleID



########################################
## CONNECT
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
exports.connect = (url, cbConnected) ->
  amqpUrl = url ? "amqp://guest:guest@localhost:5672//" # default to localhost if no environment variable is set
  amqpUrlSafe = amqpUrl.substring amqpUrl.indexOf "@"  # Safe to log this value (strip password out of url)
  
  if not conn?
    elma.info "rabbitConnecting", "Connecting to RabbitMQ #{amqpUrlSafe}..."
    conn = amqp.createConnection {heartbeat: 10, url: url} # create the connection
    conn.on "error", (err) ->
      elma.error "rabbitConnectedError", "RabbitMQ server at #{amqpUrlSafe} reports ERROR.", err
    conn.on "ready", (err) ->
      elma.info "rabbitConnected", "Connected to RabbitMQ #{amqpUrlSafe}"
      if err?
        elma.error "rabbitConnectError", "Connection to RabbitMQ server at #{amqpUrlSafe} FAILED.", err
        cbConnected err
        return
      connectionReady = true
      cbConnected undefined
  else
    deferUntil exports.ready, cbConnected, undefined



########################################
## DELETE
########################################

###
  Force delete of a queue (for maintainence/dev use)
###
# NOTE: this is broken - no cbDone callback
# exports.delete = () ->
#   #Unsubscribe any active listener
#   if queues[typeResponse]?  
#     #Delete Queue
#     queues[typeResponse].destroy {ifEmpty: false, ifUnused: false}
#     #Update global state
#     queues[typeResponse] = undefined
#     listeners[typeResponse] = undefined
#     cbDone undefined
#   else
#     cbDone "Not currently aware of #{typeResponse}! You can't blind delete."



########################################
## PUBLISH (SUBMIT)
########################################

###
  Publish (RabbitMQ terminology) a message to the specified queue
  -- Asynchronous, but callback is ignored
###
exports.publish = (queueName, messageObject, headerObject, cb) ->
  conn.publish queueName, JSON.stringify(messageObject), {contentType: "application/json", headers: headerObject}, (errorFlag, error, etc...) ->
    # if (errorFlag is true) and error?
    #   cb error, etc... # Use normal node convention for error handling (amqp passes (true, error) to its callback when an error occurs)
    # if (errorFlag is false) and error?
    #   cb undefined, arguments[1..]...
    # else
    #   cb arguments...
    return
  cb()

###
  Submit a job
  -- Enforces job structure to make future refactor work safer  
###
exports.submit = (type, payload, headers, cb) => 
    return exports.publish type, payload, headers, cb

###
  Create the externally visible job key 
  -- Job chains must have unique external keys, even though this isn't enforced at present
###
exports.jobName = (job) ->
  return "#{job.type}-#{job.name}"

########################################
## SUBSCRIBE (LISTEN)
########################################

###
  Implements listening behavior.
  -- Prevents subscribing to a queue multiple times
  -- Records the consumer-tag so you can unsubscribe
###
exports.listen = (type, cbExecute, exclusive, persist, useAcks, cbListening) ->
  amqpUrlSafe = amqpUrl.substring amqpUrl.indexOf "@" # Safe to log this value (strip password out of url)
  if not connectionReady 
    cbListening elma.error "noRabbitError", "Not connected to #{amqpUrlSafe} yet!" 
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
        queue
          .subscribe({ack: useAcks, prefetchCount: 1, exclusive: exclusive}, cbExecute)
          .addCallback((ok) -> listeners[type] = ok.consumerTag)
      cbListening undefined
  else
    if not listeners[type]? #already listening?
      queues[type]
        .subscribe({ack: useAcks, prefetchCount: 1, exclusive: exclusive}, cbExecute)
        .addCallback((ok) -> listeners[type] = ok.consumerTag) # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
    cbListening undefined



########################################
## ACKNOWLEDGE
########################################

###
  Acknowledge the last job received of the specified type
  -- type: type of job you are ack'ing (you get only 1 job of any type at a time, but can subscribe to multiple types)
  -- cbAcknowledged: callback after ack is sent successfully
###
exports.acknowledge = (type, cbAcknowledged) =>
  amqpUrlSafe = amqpUrl.substring amqpUrl.indexOf "@"
  if not connectionReady 
    cbAcknowledged elma.error "noRabbitError", "Not connected to #{amqpUrlSafe} yet!" 
    return
  if not queues[type]?
    cbAcknowledged "Connection to queue for job type #{type} not available! Are you listening to this queue?"
    return
  queues[type].shift()
  cbAcknowledged undefined

