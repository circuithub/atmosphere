########################################
## OPERATIONS
########################################

###
  Trigger jobs on a periodic basis
  > Warning: HALO reference
  > We don't care about response or failures 
  > it's just a trigger call (we'll auto retry anyway if it failed)
  -- jobName: queue name
  -- jobData: submitted with job
  -- jobTimeout: in seconds
  -- repeatPeriod: in seconds. Repeats job this many seconds *after* job completes.
###
guiltySpark = (jobName, jobData, jobTimeout, repeatPeriod) =>
  #Make atmosphere request
  console.log "[WAKE]", "Making request", jobName
  atmosphere.rainMaker.submit {type: jobName, name: jobName, data: jobData, timeout: jobTimeout}, (err, data) => #5min timeout
    if err?
      console.log "[ESUBMIT]", "Submission of #{jobName} failed.", err
    else  
      console.log "[JSUCCESS]", "Job #{jobName} completed.", data
      try
        #Log Report
        check(data).notNull().isUrl()          
        reports[jobName].url = data        
      catch e
        console.log "[WNODATA]", "Job #{jobName} did not return a valid report URL.", e
        return  
    #Recycle
    console.log "[SLEEP]", "#{jobName} resting for #{repeatPeriod} seconds."
    setTimeout () => 
      guiltySpark jobName, jobData, jobTimeout, repeatPeriod
    , repeatPeriod * 1000

_workerName = (fromID) ->
  nameBits = fromID.split("-")
  return "#{nameBits[0]}:#{nameBits[1][0...4]}"

_jobMessage = (message, headers, deliveryInfo) ->
  headers.task = JSON.parse(headers.task) if typeof headers.task is "string"
  if message?.level isnt "heartbeat"
    console.log "[RECEIVED]", JSON.stringify(message), JSON.stringify(headers)
  theMessage = {
    when: new Date()
    class: 
      type: headers.task.type
      name: headers.task.name
      step: headers.task.step
    msg: message
      # level: message.level
      # message: message.message
      # data: message.data
    }
  return theMessage

  

###
  Warning: HALO reference
  > Listen for and process incoming status messages from app servers executing DIS tasks
  Useful data formats and structures:
  -- message = {level: "start", message: message provided by job, data: data attached by job}
  -- headers.task = {type: , job:{name: , id:}, step: <optional>} -- job ticket
  -- deliveryInfo.queue = name of queue where delivered
###
cortana = (message, headers, deliveryInfo) =>

  
###
  Warning: HALO reference
  > Discover & clenanup dead workers
###
theChief = () ->
  now = new Date().getTime()
  for workerName, worker of workers
    if now - worker.alive > 4000
      delete workers[workerName] #dead worker!
  setTimeout () ->
    theChief()
  , 1000