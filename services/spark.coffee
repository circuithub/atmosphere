rainMaker = require "../lib/rain.maker"
{check}    = require "validator"

########################################
## OPERATIONS
########################################

###
  Trigger jobs on a periodic basis
  > We don't care about response or failures 
  > it's just a trigger call (we'll auto retry anyway if it failed)
  -- jobName: queue name
  -- jobData: submitted with job
  -- jobTimeout: in seconds
  -- repeatPeriod: in seconds. Repeats job this many seconds *after* job completes.
###
exports.register = (jobName, jobData, jobTimeout, repeatPeriod) =>
  #Make atmosphere request
  console.log "[WAKE]", "Making request", jobName
  rainMaker.submit {type: jobName, name: jobName, data: jobData, timeout: jobTimeout}, (err, data) =>
    if err?
      console.log "[ESUBMIT]", "Submission of #{jobName} failed.", err
    else  
      console.log "[JSUCCESS]", "Job #{jobName} completed.", data
      try
        #Log Report
        check(data).notNull().isUrl()          
        #TODO write the report URL to firebase somewhere: data is a string URL containing S3 location of the report
      catch e
        console.log "[WNODATA]", "Job #{jobName} did not return a valid report URL.", e
        return  
    #Recycle
    console.log "[SLEEP]", "#{jobName} resting for #{repeatPeriod} seconds."
    setTimeout () => 
      @register jobName, jobData, jobTimeout, repeatPeriod
    , repeatPeriod * 1000
