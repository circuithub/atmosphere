core = require "./core"
os = require "os"

perfMon =
  complete: 0
  running: 0
  startTime: undefined #time stamp exited initialization
  idleAt: undefined #last job completed at (timestamp)

###
  RainCloud: Just booted
###
exports.boot = () ->
  core.refs().rainCloudsRef.child("#{core.rainID()}/log/start").set core.now()

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
  core.refs().rainCloudsRef.child("#{core.rainID()}/status/completed").transaction updateFunction, onComplete

###
  RainCloud: Monitor and report system load metrics
  http://juliano.info/en/Blog:Memory_Leak/Understanding_the_Linux_load_average
###
exports.system = () ->
  if core.ready()
    core.refs().rainCloudsRef.child("#{core.rainID()}/status/load").set os.loadavg()
  setTimeout exports.system, 1000

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
    core.refs().rainDropsRef.child("#{rainDropID}/log/#{event}").set core.log rainDropID, event, where