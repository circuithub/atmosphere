nconf = require "nconf"
elma  = require("elma")(nconf)

core = require "./core"

########################################
## BUCKET JOBS (receive and log)
########################################

###
  Listen for messages
  -- Queue persists
  -- Non-exclusive access
  -- Auto-ack (e.g. stream) incoming messages
###
exports.listen = (type, cbExecute, cbListening) =>
  core.listen type, cbExecute, false, true, false, cbListening

###
  Submit a task (status message) to the queue (no response)
  -- type: type of task (name of task queue)
  -- ticket: Job Ticket. Must be in this format {job: {name: "taskName", id:"uuid"}, type: "taskQueueName"} 
  -- task: Message and data. Format: {message: "", level: "warning", data: {} }
  -- cbSubmitted: callback when submission complete (err, data) format
###
exports.submit = (type, ticket, task, cbSubmitted) =>
  if not connectionReady 
    cbSubmitted [elma.error("noRabbitError", "Not connected to #{urlLogSafe} yet!")]
    return
  #[1.] Submit Task Message
  core.publish type, task, {task: ticket, fromID: rainID}
  cbSubmitted()





