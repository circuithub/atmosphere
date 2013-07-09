_            = require "underscore"
should       = require "should"
atmosphere   = require "../index"
bsync        = require "bsync"
h            = require "./helpers"



###############################
## RAINCLOUD Config

altiumCounter = 0

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
  data2 = {previous: data, first: "results from worker 1"}
  atmosphere.rainCloud.doneWith ticket, undefined, data2

worker2 = (ticket, data) ->
  console.log "[W] SECOND", ticket, data 
  count()
  data2 = {previous: data, second: "results from worker 2"}
  atmosphere.rainCloud.doneWith ticket, undefined, data2

worker3 = (ticket, data) ->
  console.log "[W] THIRD", ticket, data 
  count()
  data2 = {previous: data, third: "results from worker 3"}
  atmosphere.rainCloud.doneWith ticket, undefined, data2

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
  console.log "[#] Maker: #{atmosphere.rainMaker.count()}; Cloud: #{JSON.stringify atmosphere.rainCloud.count()}."


do ->
  #Init Cloud (Worker Server)
  atmosphere.rainCloud.init "Cloud", undefined, undefined, jobTypes, (err) ->
    h.shouldNotHaveErrors err
    console.log "[I] Initialized RAINCLOUD", err
