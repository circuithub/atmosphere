_               = require "underscore"
should          = require "should"
atmosphere      = require "../index"
bsync           = require "bsync"
h               = require "./helpers"
nconf           = require "nconf"

nconf.env()

firebaseTestURL = nconf.get("FIREBASE_URL")


###############################
## RAINCLOUD Config

altiumCounter = 0
workTimeMs = 1500

workerDoAltium = (ticket, data) ->
  console.log "[W] ALTIUM", ticket, data 
  count()
  altiumCounter++
  atmosphere.rainCloud.doneWith ticket, undefined, {result:"Done with Altium", count: altiumCounter}

workerDoOrCAD = (ticket, data) ->
  console.log "[W] ORCAD", ticket, data
  atmosphere.rainCloud.doneWith ticket, undefined, "Done with ORCAD job"

worker1 = (ticket, data) ->
  console.log "[W] FIRST", ticket, data 
  count()
  data2 = {input: data, first: "results from worker 1"}
  setTimeout () ->
    atmosphere.rainCloud.doneWith ticket, undefined, data2
  , workTimeMs

worker2 = (ticket, data) ->
  console.log "[W] SECOND", ticket, data 
  count()
  data2 = {input: data, second: "results from worker 2"}
  setTimeout () ->
    atmosphere.rainCloud.doneWith ticket, undefined, data2
  , workTimeMs

worker3 = (ticket, data) ->
  console.log "[W] THIRD", ticket, data 
  count()
  data2 = {input: data, third: "results from worker 3"}
  setTimeout () ->
    atmosphere.rainCloud.doneWith ticket, undefined, data2
  , workTimeMs

workerJobJob = (ticket, data) ->
  console.log "[W] JOB-JOB", ticket, data
  count()
  job1 = 
    type: "first" #the job type/queue name
    name: "innerJob" #name for this job
    data: {fourth: "Internal Job Data"}
    timeout: 5 #seconds
  atmosphere.rainMaker.submit job1, (err, resp) ->
    atmosphere.rainCloud.doneWith ticket, err, resp  



jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
  first: worker1
  second: worker2
  third: worker3
  jobjob: workerJobJob
  jobjobjob: workerJobJob
}



count = () ->
  #Reporting when necessary  


do ->
  #Init Cloud (Worker Server)
  atmosphere.rainCloud.init "Cloud", {url: firebaseTestURL}, jobTypes, (err) ->
    h.shouldNotHaveErrors err
    console.log "[I] Initialized RAINCLOUD", err
