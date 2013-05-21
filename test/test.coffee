should       = require "should"
atmosphere = require "../index"
bsync = require "bsync"


###############################
## HELPERS

shouldNotHaveErrors = (errors) ->
  if errors?
    console.log "\n\n\n=-=-=[shouldNotHaveErrors]", errors, "\n\n\n" #xxx
    if Array.isArray errors
      errorsString = (for e in errors then "#{e.code}: #{e.message}").join "\n"
      should.fail errorsString, ""
    else
      errorsString = (for k,e of errors then "#{e.code}: #{e.message}").join "\n"
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
  (return true) for error in errors when error.code is errorCode
  return false

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

jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
}

withTester = (ticket, data) ->
  console.log "[Ww] Listen/Submit With Tester", ticket, data

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

  it "should process two different job types simultaneously", (done) ->
    testFunctions = 
      job1: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
      job2: bsync.apply atmosphere.rainMaker.submit, {type: "convertOrCAD", name: "job-orcad1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}
    bsync.parallel testFunctions, (allErrors, allResults) ->
      shouldNotHaveErrors allErrors
      console.log "[D] Jobs Done", allResults      
      done()

  it "should process only one job of a type at a time", (done) ->
    testFunctions = []
    for i in [0...10]
      #Submit Altium Conversion Job
      testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-altium-loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
      bsync.parallel testFunctions, (allErrors, allResults) ->
        shouldNotHaveErrors allErrors
        console.log "[D] Job Done", allResults
        done()

  #-- NOTE: Support for this isn't rigorous. Jobs must be safe to run on top of itself, but this makes it more efficient since if the same job is routed to the same cloud it will be dropped.
  it "should handle a job collision (same job submitted simultaneously)", (done) ->
    testFunctions = 
      job1: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}
      job2: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}  
      job3: bsync.apply atmosphere.rainMaker.submit, {type: "convertAltium", name: "job-collision", data: {}, timeout:2}
    bsync.parallel testFunctions, (allErrors, allResults) ->
      shouldHaveErrors allErrors
      console.log "\n\n\n=-=-=[error test]", allErrors, "\n\n\n" #xxx
      done()

#     #Test ...With functions
#     atmosphere.rainBucket.listen "testSubmitWith", withTester, (err) ->
#       atmosphere.rainBucket.submit "testSubmitWith", {type: "testSubmitWith", job: {name: "first-test", id: 42}}, "DATA!", (err) ->
#         console.log "[Sw] Submitted.", err

#     #Stress Test (~33 Megabyte Payload)
#     stressString = "asldjlsdijf ailjlafjlwjf asdkjfaasdfasdfas dvc827498skdjfkjfdifiesjkjkjkjkjkjlkjlljlkjljhghgjfghfhgfhgfhjgfjhgfjhgfjhgfjhgfhjgfghjfjhgfhghjgffslfksjsfifjofsfs98w798457234984328943274328743298423743298742398742398423748237432987423984239842379834243928743rweufewhjfdjkfshjkfsjhkfsjkhfsuiywye7423764794748423khejfjhkfsjhfyuirey254232uejkhfhkjfsjhkuyiwreyui5w397yurewhjkfj27492874982b 2398v982vn82vnv  2v984 2948v 92 24v42 478 4978 42v3798 4v23 98742v39898 798 29sj fklsdj fksadj fasdj fsadj fl fwreiruoweru lsdjflsadj flasdvnv xcnv,xnv ,mxvl lvknsvlaksndv,m xcnva jksdhfk jsdhf nm,vc aks jd nc sdcn k jaewh fkjashfhasdkbfvnhsnfdsnvfnhafksdnkahnfljadnkvnalhnflksnfashnfashnknhasfnasdhuwiqyeruwqygr65784659h2378465g87965987236589723459762485gy63uthkrhfgkjdfnhgvcxmnvnmcxbvjkhdshfjkdhfuityretiy84765387256093475923475823u5twhdkgfhkjfhgkjdncxnbvnmbnmcvbvjkdhgkjdfyhtuieryt9w34759843759843tuiwegkdhsfgjkhdsjfgnm,cvvbnm,xcnvbmxzcnvz,xcmnvkjdfhgusidktyiuer7y69854376598043769083769843576rewojutglkdfghj,cjnbm,ncvnbx,m"
#     stressString += stressString for i in [0...15] 
#     console.log "Stressing Rabbit... #{(stressString.length/1e6).toFixed(2)} MB"
#     atmosphere.rainMaker.submit {type: "partsWithoutImages", name:"stress", data: {values: stressString}, timeout: 10}, (err, report) ->
#       console.log "done!", err, report
#     atmosphere.rainBucket.listen "partsWithoutImages"
#     , (message, headers, deliveryInfo) ->
#       console.log "RECEIVED!", deliveryInfo
#     , () ->
#       console.log "done! 2"


# setTimeout () ->
#   count()
# , 1000

# count()
# console.log "EOF"