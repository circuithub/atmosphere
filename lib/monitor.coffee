core = require "./core"

perfMon =
  complete: 0
  running: 0
  startTime: undefined #time stamp exited initialization
  idleAt: undefined #last job completed at (timestamp)

exports.boot = () ->
  perfMon.startTime = new Date().getTime() #log boot time

exports.jobComplete = () ->
  perfMon.complete++
  perfMon.idleAt = new Date().getTime()

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
  Write to rainDrop's event log
###
exports.log = (rainDropID, event, where) =>
  core.refs().rainDropsRef.child("#{rainDropID}/log/#{event}").set core.log where