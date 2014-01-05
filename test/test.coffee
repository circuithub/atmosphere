_            = require "underscore"
should       = require "should"
atmosphere   = require "../index"
bsync        = require "bsync"
h            = require "./helpers"

console.log "\n\n\n=-=-=[START]", "Make sure that test.rain.cloud is running...", "\n\n\n" #xxx

count = () ->
  console.log "[#] Maker: #{atmosphere.rainMaker.count()}; Cloud: #{JSON.stringify atmosphere.rainCloud.count()}."

withTester = (ticket, data) ->
  ticket.data = {}
  console.log "[Ww] Listen/Submit With Tester", ticket


###############################
## RUN ME! Yay! Tests!

describe "atmosphere", ->
  
  before (done) ->
    #Init Rainmaker (App Server)
    atmosphere.rainMaker.init null, "rainMaker", (err) ->
      h.shouldNotHaveErrors err
      console.log "[I] Initialized RAINMAKER", err
      done()

  describe "#basic RPC use case", ->  
  
    it "should process two different job types simultaneously", (done) ->
      testFunctions = 
        job1: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
        job2: bsync.apply atmosphere.rainMaker.submit, {type: "convertOrCAD", name: "job-orcad1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
      bsync.parallel testFunctions, (allErrors, allResults) ->
        h.shouldNotHaveErrors allErrors
        console.log "[D] Jobs Done", allResults      
        done()

    it "should process only one job of a type at a time", (done) ->
      testFunctions = []
      for i in [0...10]
        #Submit Altium Conversion Job
        testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium-loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
      bsync.parallel testFunctions, (allErrors, allResults) ->
        h.shouldNotHaveErrors allErrors
        console.log "[D] Job Done", allResults
        done()

  describe "#complex RPC use case (job chaining)", ->
        
    it "should handle a job->job->job->callback job chain", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 30 #seconds
      job2 = 
        type: "second"        
        data: {param2: "initial message"} #merged with results from job1        
      job3 = 
        type: "third"
        data: {param3: "initial message"} #merged with results from job1
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        console.log "\n\n\n=-=-=[jjjc]", JSON.stringify(data), "\n\n\n" #xxx
        h.shouldNotHaveErrors error
        should.exist data
        should.exist data[job3.type]
        should.exist data.previous.param3
        should.exist data.previous[job2.type].previous.param2
        should.exist data.previous[job2.type].previous[job1.type].previous.param1
        done()

    it "should handle a job->job->callback->job chain", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 5 #seconds
      job2 = 
        type: "second"
        data: {param2: "initial message"} #merged with results from job1
        callback: true
      job3 = 
        type: "third"
        data: {param3: "initial message"} #merged with results from job1
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        console.log "\n\n\n=-=-=[jjcj]", JSON.stringify(data), "\n\n\n" #xxx
        h.shouldNotHaveErrors error
        should.exist data        
        should.exist data.previous.param2
        should.exist data.previous[job1.type].previous.param1
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
        data: {param2: "initial message"} #merged with results from job1
      job3 = 
        type: "third"
        data: {param3: "initial message"} #merged with results from job1
      atmosphere.rainMaker.submit [job1, job2, job3], (error, data) ->
        console.log "\n\n\n=-=-=[jcjj]", JSON.stringify(data), "\n\n\n" #xxx
        h.shouldNotHaveErrors error
        should.exist data 
        should.exist data.first       
        should.exist data.previous.param1
        done()

    it "should handle a job->job->job chain (fire-and-forget)", (done) ->
      job1 = 
        type: "first" #the job type/queue name
        name: "job1" #name for this job
        data: {param1: "initial message"} #arbitrary serializable object
        timeout: 5 #seconds
      job2 = 
        type: "second"
        data: {param2: "initial message"} #merged with results from job1
      job3 = 
        type: "third"
        data: {param3: "initial message"} #merged with results from job1
      console.log "\n\n\n=-=-=[jjj]", "beginning...", "\n\n\n" #xxx
      atmosphere.rainMaker.submit [job1, job2, job3], undefined
      done()

    it "should route results from jobs that call jobs correctly", (done) ->
      job = 
        type: "jobjob"
        name: "linkTest"
        data: {param3: "initial message"}
      console.log "\n\n\n=-=-=[j->j]", "beginning...", "\n\n\n" #xxx
      atmosphere.rainMaker.submit job, (err, resp) ->
        console.log "\n\n\n=-=-=[j->j]", err, resp, "\n\n\n" #xxx
        h.shouldNotHaveErrors err
        should.exist resp   
        should.exist resp.first
        should.exist resp.previous
        should.exist resp.previous.fourth     
        done()

  describe "#logging use case", ->

    before (done) ->    
      atmosphere.rainBucket.listen "testSubmitWith", withTester, (err) ->
        h.shouldNotHaveErrors err
        done()

    it "should be able to submit a logging message", (done) ->
      atmosphere.rainBucket.submit "testSubmitWith", {type: "testSubmitWith", job: {name: "first-test", id: 42}}, "DATA!", (err) ->
        h.shouldNotHaveErrors err
        console.log "[Sw] Submitted.", err
        done()

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