amqp = require "amqp"
nconf = require "nconf"
elma  = require("elma")(nconf)

url = nconf.get("CLOUDAMQP_URL") or "amqp://brkoacph:UNIBQBLE1E-_t-6fFapavZaMN68sdRVU@tiger.cloudamqp.com/brkoacph" # default to circuithub-staging
conn = undefined
connectionReady = false
@connect()

###
	Connect to specified RabbitMQ server, callback when done.
	-- This is done automatically at the first module loading
	-- However, this method is exposed in case, you want to explicitly wait it out and confirm valid connection in app start-up sequence
	-- Connection is enforced, so if connection doesn't exist, nothing else will work.
###
exports.connect = (cbConnected) ->
	conn = amqp.createConnection {url: url} # create the connection
	conn.on "ready", (err) ->
		if err?
			elma.error "Connection to RabbitMQ server at #{url} FAILED.", err
			cbConnected err
			return
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

exports.acknowledge = (type, cbAcknowledged) =>
	if not connectionReady 
		cbListening "Connection to #{url} not ready yet!" 
		return
	queue = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		queue.shift()

###
	submit a job to the queue
	-- type: type of job (name of job queue)
	-- data: the job details (message body)
###
exports.submit = (type, data, cbSubmitted) =>
	if not connectionReady 
		cbSubmitted "Connection to #{url} not ready yet!" 
		return
	queue = conn.queue type, {}, () -> # create a queue (if not exist, sanity check otherwise)
		conn.publish type, data
		cbSubmitted undefined

###
	Find existing pending jobs in the queue
###
exports.search = (searchTerms) =>
	return jobs.search(searchTerms)

