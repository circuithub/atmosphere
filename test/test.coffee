_ = require "underscore"
should       = require "should"
atmosphere = require "../index"
bsync = require "bsync"


###############################
## HELPERS

shouldNotHaveErrors = (errors) ->
  if errors?
    errorsString = ""
    if Array.isArray errors
      errorsString = (for e in errors then "#{e?.code}: #{e?.message}").join "\n"      
    else
      if errors.code?
        errorsString = (for k,e of errors then "#{e?.code}: #{e?.message}").join "\n"    
      else
        for k, job of errors 
          errorsString += (for k,e of job then "#{e?.code}: #{e?.message}").join "\n"    
    should.fail errorsString, ""
      
#Allowed Error Formats:
#Array:
#   [ {id, code, message}, undefined, {id, code, message}, ... ]  ---  array of objects, undefined (no errors) allowed
#Object:
#   { 
#       keyName1: [ {id, code, message}, undefined, {id, code, message}, ... ] 
#       keyName2: undefined
#   }
shouldHaveErrors = (errors) ->
  should.exist errors
  if Array.isArray errors    
    errors.should.not.be.empty
    for e in errors
      should.exist e.id
      should.exist e.code
      should.exist e.message
  else
    errors.should.be.an.instanceof Object # (Must be a circuithub error)
    keys = _.keys errors
    for i in [0...keys.length]
      value = errors[keys[i]]
      if value?      
        should.exist value[0].id
        should.exist value[0].code
        should.exist value[0].message

#Determines is a specific error occurred
shouldHaveError = (errors, errorCode) ->  
  shouldHaveErrors errors
  errorCodeExists = false
  return error for error in errors when error.code is errorCode
  errorCodeExists.should.equal true

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
  data.first = "results from worker 1"
  atmosphere.rainCloud.doneWith ticket, undefined, data

worker2 = (ticket, data) ->
  console.log "[W] SECOND", ticket, data 
  count()
  data.second = "results from worker 2"
  atmosphere.rainCloud.doneWith ticket, undefined, data

worker3 = (ticket, data) ->
  console.log "[W] THIRD", ticket, data 
  count()
  data.third = "results from worker 3"
  atmosphere.rainCloud.doneWith ticket, undefined, data

jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
  first: worker1
  second: worker2
  third: worker3
}

withTester = (ticket, data) ->
  ticket.data = {}
  console.log "[Ww] Listen/Submit With Tester", ticket

count = () ->
  console.log "[#] Maker: #{atmosphere.rainMaker.count()}; Cloud: #{JSON.stringify atmosphere.rainCloud.count()}."



###############################
## RUN ME! Yay! Tests!

describe "atmosphere", ->
  
  before (done) ->
    #Init Cloud (Worker Server -- ex. EDA Server)
    atmosphere.rainCloud.init "test", jobTypes, (err) ->
      shouldNotHaveErrors err
      console.log "[I] Initialized RAINCLOUD", err
      
      #Init Rainmaker (App Server)
      atmosphere.rainMaker.init "test", (err) ->
        shouldNotHaveErrors err
        console.log "[I] Initialized RAINMAKER", err
        done()

  # describe "#basic RPC use case", ->  
  
  #   it "should process two different job types simultaneously", (done) ->
  #     testFunctions = 
  #       job1: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
  #       job2: bsync.apply atmosphere.rainMaker.submit, {type: "convertOrCAD", name: "job-orcad1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
  #     bsync.parallel testFunctions, (allErrors, allResults) ->
  #       shouldNotHaveErrors allErrors
  #       console.log "[D] Jobs Done", allResults      
  #       done()

  #   it "should process only one job of a type at a time", (done) ->
  #     testFunctions = []
  #     for i in [0...10]
  #       #Submit Altium Conversion Job
  #       testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium-loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
  #     bsync.parallel testFunctions, (allErrors, allResults) ->
  #       shouldNotHaveErrors allErrors
  #       console.log "[D] Job Done", allResults
  #       done()

  #   #-- NOTE: Support for this isn't rigorous. Jobs must be safe to run on top of itself, but this makes it more efficient since if the same job is routed to the same cloud it will be dropped.
  #   it "should handle a job collision (same job submitted simultaneously)", (done) ->
  #     testFunctions = 
  #       job1: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}
  #       job2: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}  
  #       job3: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}
  #     bsync.parallel testFunctions, (allErrors, allResults) ->
  #       console.log "\n\n\n=-=-=[error test]", allErrors, "\n\n\n" #xxx
  #       shouldHaveError [allErrors.job2, allErrors.job3], "jobAlreadyExistsError"
  #       done()

  describe "#complex RPC use case (job chaining)", ->
    
    before (done) ->
      done()
    
    it "should handle a job->job->job->callback job chain", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 30 #seconds
      job2 = 
        type: "second"
        name: "job2"
        data: {param2: "initial message"} #merged with results from job1
        timeout: 15 #in seconds; clock starts running at start of execution
      job3 = 
        type: "third"
        name: "job3"
        data: {param3: "initial message"} #merged with results from job1
        timeout: 15 #in seconds; clock starts running at start of execution
      console.log "\n\n\n=-=-=[TEST1]", atmosphere.rainMaker._jobs, "\n\n\n" #xxx
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        console.log "\n\n\n=-=-=[TEST2]", atmosphere.rainMaker._jobs, "\n\n\n" #xxx
        shouldNotHaveErrors error
        should.exist data
        should.exist data.first
        should.exist data.second
        should.exist data.third
        done()

    it "should handle a job->job->callback->job chain", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 5 #seconds
      job2 = 
        type: "second"
        name: "job2"
        data: {param2: "initial message"} #merged with results from job1
        timeout: 5 #in seconds; clock starts running at start of execution
        callback: true
      job3 = 
        type: "third"
        name: "job3"
        data: {param3: "initial message"} #merged with results from job1
        timeout: 5 #in seconds; clock starts running at start of execution
      console.log "\n\n\n=-=-=[TEST3]", atmosphere.rainMaker._jobs, "\n\n\n" #xxx
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        console.log "\n\n\n=-=-=[TEST4]", atmosphere.rainMaker._jobs, "\n\n\n" #xxx
        console.log "\n\n\n=-=-=[jjcj]", error, data, "\n\n\n" #xxx
        shouldNotHaveErrors error
        should.exist data
        should.exist data.first
        should.exist data.second
        should.not.exist data.third
        done()

    it "should handle a job->callback->job->job chain", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 5 #seconds
        callback: true
      job2 = 
        type: "second"
        name: "job2"
        data: {param2: "initial message"} #merged with results from job1
        timeout: 5 #in seconds; clock starts running at start of execution
      job3 = 
        type: "third"
        name: "job3"
        data: {param3: "initial message"} #merged with results from job1
        timeout: 5 #in seconds; clock starts running at start of execution
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        shouldNotHaveErrors error
        should.exist data
        should.exist data.first
        should.not.exist data.second
        should.not.exist data.third
        done()

  # describe "#logging use case", ->

  #   before (done) ->    
  #     atmosphere.rainBucket.listen "testSubmitWith", withTester, (err) ->
  #       shouldNotHaveErrors err
  #       done()

  #   it "should be able to submit a logging message", (done) ->
  #     atmosphere.rainBucket.submit "testSubmitWith", {type: "testSubmitWith", job: {name: "first-test", id: 42}}, "DATA!", (err) ->
  #       shouldNotHaveErrors err
  #       console.log "[Sw] Submitted.", err
  #       done()

  #   it "should survive extremely large message", (done) ->
  #     #Stress Test (~33 Megabyte Payload)
  #     stressString = "asldjlsdijf ailjlafjlwjf asdkjfaasdfasdfas dvc827498skdjfkjfdifiesjkjkjkjkjkjlkjlljlkjljhghgjfghfhgfhgfhjgfjhgfjhgfjhgfjhgfhjgfghjfjhgfhghjgffslfksjsfifjofsfs98w798457234984328943274328743298423743298742398742398423748237432987423984239842379834243928743rweufewhjfdjkfshjkfsjhkfsjkhfsuiywye7423764794748423khejfjhkfsjhfyuirey254232uejkhfhkjfsjhkuyiwreyui5w397yurewhjkfj27492874982b 2398v982vn82vnv  2v984 2948v 92 24v42 478 4978 42v3798 4v23 98742v39898 798 29sj fklsdj fksadj fasdj fsadj fl fwreiruoweru lsdjflsadj flasdvnv xcnv,xnv ,mxvl lvknsvlaksndv,m xcnva jksdhfk jsdhf nm,vc aks jd nc sdcn k jaewh fkjashfhasdkbfvnhsnfdsnvfnhafksdnkahnfljadnkvnalhnflksnfashnfashnknhasfnasdhuwiqyeruwqygr65784659h2378465g87965987236589723459762485gy63uthkrhfgkjdfnhgvcxmnvnmcxbvjkhdshfjkdhfuityretiy84765387256093475923475823u5twhdkgfhkjfhgkjdncxnbvnmbnmcvbvjkdhgkjdfyhtuieryt9w34759843759843tuiwegkdhsfgjkhdsjfgnm,cvvbnm,xcnvbmxzcnvz,xcmnvkjdfhgusidktyiuer7y69854376598043769083769843576rewojutglkdfghj,cjnbm,ncvnbx,m"
  #     stressString += stressString for i in [0...15] 
  #     console.log "Stressing Rabbit... #{(stressString.length/1e6).toFixed(2)} MB"
  #     atmosphere.rainMaker.submit {type: "testSubmitWith", name:"stress", data: {values: stressString}, timeout: 10}, (err, report) ->
  #       console.log "\n\n\n=-=-=[stress]", "callback", "\n\n\n" #xxx
  #       shouldNotHaveErrors err
  #       console.log "done!", err, report
  #       done()