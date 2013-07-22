core = require "./core"
os = require "os"

perfMon =
  complete: 0
  running: 0
  startTime: undefined #time stamp exited initialization
  idleAt: undefined #last job completed at (timestamp)



########################################
## STATE MESSAGES
########################################
###
  RainCloud: Just booted
###
exports.boot = () =>
  core.refs().thisTypeRef.child("#{core.rainID()}/log/start").set core.now()
  @system() #Begin system monitoring

###
  RainCloud: Finished another job
###
exports.jobComplete = () ->
  updateFunction = (current_value) ->
    return current_value + 1
  onComplete = (error, committed, snapshot) ->
    if error?
      console.log "[monitor]", "ECOUNTER", "Could not increment rainCloud #{core.rainID()}'s job completion counter.", error
      return
    console.log "[monitor]", "IDOSTUFZ", "This rainCloud has finished #{snapshot.val()} jobs to date."
  core.refs().thisTypeRef.child("#{core.rainID()}/status/completed").transaction updateFunction, onComplete


########################################
## PROPRIOCEPTION
########################################

###
  RainCloud: Monitor and report system load metrics
  http://juliano.info/en/Blog:Memory_Leak/Understanding_the_Linux_load_average
###
exports.system = () ->
  if core.ready()
    #system tasks running (exponentially weighted average)
    core.refs().thisTypeRef.child("#{core.rainID()}/status/load").set os.loadavg()
    cpuUsage()
  setTimeout exports.system, 1000

cpuPrevious = undefined
cpuUsage = () ->
  cpus = os.cpus()
  timestamp = (new Date()).getTime()
  total = 
    user: 0
    nice: 0
    sys: 0
    idle: 0
    irq: 0
  for eachCPU in cpus
    for eachParam, eachValue of eachCPU.times 
      if total[eachParam]? 
        total[eachParam] += eachValue 
  if not cpuPrevious?
    cpuPrevious = 
      timestamp: (new Date()).getTime()
      total: total
  else
    delta =
      milliseconds: (new Date()).getTime() - cpuPrevious.timestamp #time delta in milliseconds (sample window)
      total: 0
    #collect raw time metrics
    for eachParam of total
      delta[eachParam] = total[eachParam] - cpuPrevious.total[eachParam] 
      delta.total += delta[eachParam]    
    #convert to percent
    for eachParam of total
      delta[eachParam] = delta[eachParam]/delta.total
    #update prior state
    cpuPrevious = 
      timestamp: timestamp
      total: total
    #write to database
    core.refs().thisTypeRef.child("#{core.rainID()}/status/cpu").set delta   

exports.stats = () =>
  s = 
    complete: perfMon.complete
    running: perfMon.running
    uptime: @uptime()
    idleTime: if perfMon.running is 0 then @idletime() else 0
  return s

# In Minutes
exports.uptime = () ->
  return ((new Date().getTime() - perfMon.startTime)/1000/60).toFixed(2) #in minutes

exports.idletime = () ->
  return new Date().getTime() - perfMon.idleAt #milliseconds since last job completed



###
  RainDrop: Write to rainDrop's event log
###
exports.log = (rainDropID, event, where) =>
  if event? and event.length > 0
    core.refs().thisTypeRef.child("#{rainDropID}/log/#{event}").set core.log rainDropID, event, where