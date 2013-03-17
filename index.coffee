amqp = require "amqp"
nconf = require "nconf"
elma  = require("elma")(nconf)

url = nconf.get("CLOUDAMQP_URL") or "amqp://brkoacph:UNIBQBLE1E-_t-6fFapavZaMN68sdRVU@tiger.cloudamqp.com/brkoacph" # default to circuithub-staging
conn = undefined
connectionReady = false

queues = {}
listeners = {}

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
	conn.on "ready", (err) ->
		elma.info "Connected to RabbitMQ!"
		if err?
			elma.error "Connection to RabbitMQ server at #{url} FAILED.", err
			cbConnected err
			return
		connectionReady = true
		cbConnected undefined



########################################
## ONE-WAY API (actions w/o response)
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
	conn.publish type, job, {contentType: "application/json"}	

###
	Subscribe to incoming jobs in the queue (non-exclusively)
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
## TWO-WAY API (anticipating a response)
########################################

###
	Submit a job to the queue, but anticipate a response
	-- type: type of job (name of job queue)
	-- type: type of the job's response (name of the response queue)
	-- data: the job details (message body)
	-- cbResponse: callback when response received
	-- cbSubmitted: callback when submition complete
###
exports.submitFor = (type, typeResponse, data, cbResponse, cbSubmitted) =>
	if not connectionReady 
		cbSubmitted "Connection to #{url} not ready yet!" 
		return
	queueTX = conn.queue type, {}, () => # create a queue (if not exist, sanity check otherwise)
		queueRX = conn.queue typeResponse, {}, () =>	
			#Submit outgoing job
			job = {
				typeResponse: typeResponse
				data: JSON.stringify(data)
			}
			console.log "\n\n\n=-=-=[submitFor]", job, "\n\n\n" #xxx
			conn.publish type, job, {contentType : "application/json"}
			#Listen for incoming job responses
			@listenFor typeResponse, cbResponse, cbSubmitted

###
	Subscribe to incoming jobs in the queue (exclusively -- block others from listening)
	-- type: type of jobs to listen for (name of job queue)
	-- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
	-- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listenFor = (type, cbExecute, cbListening) =>
	_listen type, cbExecute, true, true, cbListening

###
	Stop listening for jobs of the specified job response type
	(force deletes the underlying backing queue, losing all remaining messages)
	(NOTE: Synchronous function)
###
exports.doneWith = (typeResponse) =>
	console.log "\n\n\n=-=-=[doneWith]", listeners, "\n\n\n" #xxx	
	#Unsubscribe any active listener
	queues[typeResponse].unsubscribe listeners[typeResponse] if listeners[typeResponse]?
	#Delete Queue
	queues[typeResponse].destroy {ifEmpty: false, ifUnused: false}
	#Update global state
	queues[typeResponse] = undefined
	listeners[typeResponse] = undefined



########################################
## INTERNAL / UTILITY
########################################

###
	Implements listening behavior.
###
_listen = (type, cbExecute, exclusive, persist, cbListening) =>
	if not connectionReady 
		cbListening "Connection to #{url} not ready yet!" 
		return
	if not queues[type]?
		queue = conn.queue type, {autoDelete: persist}, () -> # create a queue (if not exist, sanity check otherwise)
			queues[type] = queue #save reference so we can send acknowledgements to this queue
			queue.subscribe({ack: true, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag) # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
			cbListening undefined
	else
		if not listeners[type]? #already listening?
			queue.subscribe({ack: true, prefetchCount: 1, exclusive: exclusive}, cbExecute).addCallback((ok) -> listeners[type] = ok.consumerTag) # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
		cbListening undefined