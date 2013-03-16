amqp = require "amqp"
nconf = require "nconf"
elma  = require("elma")(nconf)

url = nconf.get("CLOUDAMQP_URL") or "amqp://brkoacph:UNIBQBLE1E-_t-6fFapavZaMN68sdRVU@tiger.cloudamqp.com/brkoacph" # default to circuithub-staging
conn = undefined
connectionReady = false

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
	console.log "\n\n\n=-=-=[connect](1)", "", "\n\n\n" #xxx
	conn = amqp.createConnection {url: url} # create the connection
	console.log "\n\n\n=-=-=[connect](2)", "", "\n\n\n" #xxx
	conn.on "ready", (err) ->
		console.log "\n\n\n=-=-=[connect](3)", "", "\n\n\n" #xxx
		if err?
			console.log "\n\n\n=-=-=[connect](4)", "", "\n\n\n" #xxx
			elma.error "Connection to RabbitMQ server at #{url} FAILED.", err
			cbConnected err
			return
		console.log "\n\n\n=-=-=[connect](5)", "", "\n\n\n" #xxx
		connectionReady = true
		cbConnected undefined

###
	Subscribe to incoming jobs in the queue
	-- type: type of jobs to listen for (name of job queue)
	-- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
	-- cbListening: callback after listening to queue has started --> function (err) 
###
exports.listenFor = (type, cbExecute, cbListening) =>
	if not connectionReady 
		cbListening "Connection to #{url} not ready yet!" 
		return
	queue = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		queue.subscribe {ack: true}, cbExecute # subscribe to the `type`-defined queue and listen for jobs one-at-a-time
		cbListening undefined

###
	Acknowledge the last job received of the specified type
	-- type: type of job you are ack'ing (you get only 1 job of any type at a time, but can subscribe to multiple types)
	-- cbAcknowledged: callback after ack is sent successfully
###
exports.acknowledge = (type, cbAcknowledged) =>
	if not connectionReady 
		cbListening "Connection to #{url} not ready yet!" 
		return
	queue = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		queue.shift()
		cbAcknowledged undefined

###
	Submit a job to the queue
	-- type: type of job (name of job queue)
	-- data: the job details (message body)
###
exports.submit = (type, data, cbSubmitted) =>
	if not connectionReady 
		cbSubmitted "Connection to #{url} not ready yet!" 
		return
	queue = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		job = {
			typeResponse: undefined
			data: JSON.stringify(data)
		}
		conn.publish type, job, {contentType : "application/json"}
		cbSubmitted undefined

###
	Submit a job to the queue
	-- type: type of job (name of job queue)
	-- data: the job details (message body)
###
exports.submitFor = (type, typeResponse, data, cbResponse, cbSubmitted) =>
	if not connectionReady 
		cbSubmitted "Connection to #{url} not ready yet!" 
		return
	queueTX = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		queueRX = conn.queue typeResponse, {}, () ->	
			#Submit outgoing job
			job = {
				typeResponse: typeResponse
				data: JSON.stringify(data)
			}
			conn.publish type, job, {contentType : "application/json"}
			#Listen for incoming job responses
			@listenFor typeResponse, cbResponse, cbSubmitted
			
#Connect to Backing Queue (RabbitMQ)
@connect () ->