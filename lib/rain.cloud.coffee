_ = require "underscore"
nconf = require "nconf"
elma  = require("elma")(nconf)
bsync = require "bsync"
{assign, pick} = require "lodash"

core = require "./core"
monitor = require "./monitor"

module.exports = -> 
  cloudRoleID = undefined
  jobWorkers = {}
  currentJobs = {}
  api = {}

  ########################################
  ## SETUP / INITIALIZATION
  ########################################  
  ###
    jobTypes -- object with jobType values and worker function callbacks as keys; { jobType1: cbDoJobType1, jobType2: .. }
    -- Safe to call this function multiple times. It adds additional job types. If exists, jobType is ignored during update.
    --role: String. 8 character (max) description of this rainCloud (example: "app", "eda", "worker", etc...)
  ###
  api.init = (role, jobTypes, cbDone) ->
    #[0.] Initialize
    if cloudRoleID?
      throw "Rain cloud has already been initialized"
    cloudRoleID = core.generateRoleID role
    #[1.] Connect to message server
    core.connect (err) ->      
      if err?
        cbDone err
        return
      #[2.] Publish all jobs we can handle (listen to all queues for these jobs)
      workerFunctions = []    
      for jobType of jobTypes
        if not jobWorkers[jobType]?
          jobWorkers[jobType] = jobTypes[jobType]
          workerFunctions.push bsync.apply api.listen, jobType, lightning
      bsync.parallel workerFunctions, (allErrors, allResults) ->
        if allErrors?
          cbDone allErrors
          return
        monitor.boot() #log boot time
        cbDone undefined

  api.getRoleID = -> cloudRoleID

  ########################################
  ## API
  ########################################
  ###
    Reports completed job on a Rain Cloud
    -- ticket: {type: "", job: {name: "", id: "uuid"} }
    -- message: the job response data (message body)
  ###
  api.doneWith = (ticket, errors, result, cb) ->

    publishResult = (job, errors, result, cb) ->
      header = assign (pick job, "job", "type"), {rainCloudID: core.rainID cloudRoleID}
      core.publish job.returnQueue, {errors, data: result}, header, cb

    publishNextJob = (currentJob, cb) ->
      # Publish result of the curent job
      publishResult currentJob, errors, result, (error) ->
        if error?
          cb error
          return
        # Get the next job in the chain
        if not currentJob.next?[0]?
          cb()
          return
        nextData = assign {}, (currentJob.next[0].data ? {})
        nextData[currentJob.type] = result # TODO: remove?
        message =
          data: nextData
          next: currentJob.next[1..] ? null
        headers =
          job: pick currentJob.job, "name", "id"
          returnQueue: currentJob.returnQueue
        core.submit currentJob.next[0].type, message, headers, cb

    if not core.ready() 
      elma.error "noRabbitError", "Not connected to #{core.urlLogSafe} yet!" 
      cb noRabbitError: "Not connected to #{core.urlLogSafe} yet!"
      return

    currentJob = currentJobs[ticket.type]
    if not currentJob?
      elma.error "noTicketWaiting", "Ticket for #{ticket.type} has no current job pending!" 
      cb noTicketWaiting: "Not connected to #{core.urlLogSafe} yet!"
      return

    elma.info "[doneWith]", "#{ticket.type}-#{ticket.name}; #{currentJob.next?.length ? 0} jobs follow. Callback? #{currentJob.callback}"
  
    publishNextJob currentJob, (error) ->
      #Done with this specific job in the job chain
      delete currentJobs[ticket.type] # done with current job, update state
      if error?
        cb error
        return
      process.nextTick ->
        core.acknowledge currentJob.type, (error) ->
          if error?
            #TODO: HANDLE THIS BETTER
            elma.error "cantAckError", "Could not send ACK", currentJob, error
            cb cantAckError: error
            return
          monitor.jobComplete()
          cb()
          return
    return
  
  ###
    Subscribe to persistent incoming jobs in the queue (non-exclusively)
    (Queue will continue to exist even if no-one is listening)
    -- type: type of jobs to listen for (name of job queue)
    -- cbExecute: function to execute when a job is assigned --> function (message, headers, deliveryInfo)
    -- cbListening: callback after listening to queue has started --> function (err)  
  ###
  api.listen = (type, cbExecute, cbListening) ->
    core.listen type, cbExecute, false, true, true, cbListening

  ###
    report RainCloud performance statistics
  ###
  api.count = () ->
    return monitor.stats()

  ###
    Object of current jobs (queue names currently being processed by this worker)
    Returns an array of queue names (job types) with active jobs in it
  ###
  api.activeJobTypes = () ->
    return Object.keys currentJobs

  ########################################
  ## STOCK ROUTERS
  ########################################

  rpcWorkers = {} #When using the simple router, stores the actual worker functions the router should invoke

  ###
    Simple direct jobs router. Fastest/easiest way to get RPC running in your app.
    --Takes in job list and wraps your function in (ticket, data) -> doneWith(..) behavior
  ###
  basic = (taskName, functionName) ->
    rpcWorkers[taskName] = functionName #save work function
    return _basicRouter

  _basicRouter = (ticket, data) ->
    elma.info "[JOB] #{ticket.type}-#{ticket.name}-#{ticket.step}"
    ticket.data = data if data? #add job data to ticket
    #Execute (invoke work function)
    rpcWorkers[ticket.type] ticket, (errors, results) ->
      # Release lower stack frames
      process.nextTick -> api.doneWith ticket, errors, results, ->

  api.routers = basic: basic


  ########################################
  ## INTERNAL OPERATIONS
  ########################################
  ###
    Receives work to do messages on cloud and dispatches
    Messages are dispatched to the callback function this way:
      function(ticket, data) ->
  ###
  lightning = (message, headers, deliveryInfo) ->
    if currentJobs[deliveryInfo.queue]?
      #PANIC! BAD STATE! We got a new job, but haven't completed previous job yet!
      elma.error "duplicateJobAssigned", "Two jobs were assigned to atmosphere.rainCloud at once! SHOULD NOT HAPPEN.", currentJobs, deliveryInfo, headers, message
      return
    #Hold this information internal to atmosphere
    currentJobs[deliveryInfo.queue] = {
      type: deliveryInfo.queue
      job: headers.job # job = {name:, id:}    
      returnQueue: headers.returnQueue
      next: message.next
      callback: headers.callback
    }
    #Release this information to the work function (dispatch job)
    ticket = 
      type: deliveryInfo.queue
      name: headers.job.name
      id: headers.job.id
    jobWorkers[deliveryInfo.queue] ticket, message.data

  return api