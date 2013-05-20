atmosphere = require "../index"

###############################
## RAINCLOUD Config

altiumCounter = 0

workerDoAltium = (ticket, data) ->
  console.log "[W] ALTIUM", ticket, data 
  count()
  altiumCounter++
  atmosphere.rainCloud.doneWith ticket, {result:"Done with Altium", count: altiumCounter}

workerDoOrCAD = (ticket, data) ->
  console.log "[W] ORCAD", ticket, data
  atmosphere.rainCloud.doneWith ticket, "Done with ORCAD job"

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

#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.rainCloud.init "test", jobTypes, (err) ->
  console.log "[I] Initialized RAINCLOUD", err
  
  #Init Rainmaker (App Server)
  atmosphere.rainMaker.init "test", (err) ->
    console.log "[I] Initialized RAINMAKER", err
    count()

    #Submit Altium Conversion Job
    atmosphere.rainMaker.submit {type: "convertAltium", name: "job-altium1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}, (err, data) ->
      console.log "[D] Job Done", err, data
      count()

    #Submit Altium Conversion Job
    atmosphere.rainMaker.submit {type: "convertOrCAD", name: "job-orcad1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}, (err, data) ->
      console.log "[D] Job Done", err, data
      count()

    for i in [0...10]
      #Submit Altium Conversion Job
      atmosphere.rainMaker.submit {type: "convertAltium", name: "job-altium-loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}, (err, data) ->
        console.log "[D] Job Done", err, data
        count()

    atmosphere.rainMaker.submit {type: "convertAltium", name: "job-collision", data: {}, timeout:2}, (error, data) ->
    atmosphere.rainMaker.submit {type: "convertAltium", name: "job-collision", data: {}, timeout:2}, (error, data) ->  
    atmosphere.rainMaker.submit {type: "convertAltium", name: "job-collision", data: {}, timeout:2}, (error, data) ->

    #Test ...With functions
    atmosphere.rainBucket.listen "testSubmitWith", withTester, (err) ->
      atmosphere.rainBucket.submit "testSubmitWith", {type: "testSubmitWith", job: {name: "first-test", id: 42}}, "DATA!", (err) ->
        console.log "[Sw] Submitted.", err

    #Stress Test (~33 Megabyte Payload)
    stressString = "asldjlsdijf ailjlafjlwjf asdkjfaasdfasdfas dvc827498skdjfkjfdifiesjkjkjkjkjkjlkjlljlkjljhghgjfghfhgfhgfhjgfjhgfjhgfjhgfjhgfhjgfghjfjhgfhghjgffslfksjsfifjofsfs98w798457234984328943274328743298423743298742398742398423748237432987423984239842379834243928743rweufewhjfdjkfshjkfsjhkfsjkhfsuiywye7423764794748423khejfjhkfsjhfyuirey254232uejkhfhkjfsjhkuyiwreyui5w397yurewhjkfj27492874982b 2398v982vn82vnv  2v984 2948v 92 24v42 478 4978 42v3798 4v23 98742v39898 798 29sj fklsdj fksadj fasdj fsadj fl fwreiruoweru lsdjflsadj flasdvnv xcnv,xnv ,mxvl lvknsvlaksndv,m xcnva jksdhfk jsdhf nm,vc aks jd nc sdcn k jaewh fkjashfhasdkbfvnhsnfdsnvfnhafksdnkahnfljadnkvnalhnflksnfashnfashnknhasfnasdhuwiqyeruwqygr65784659h2378465g87965987236589723459762485gy63uthkrhfgkjdfnhgvcxmnvnmcxbvjkhdshfjkdhfuityretiy84765387256093475923475823u5twhdkgfhkjfhgkjdncxnbvnmbnmcvbvjkdhgkjdfyhtuieryt9w34759843759843tuiwegkdhsfgjkhdsjfgnm,cvvbnm,xcnvbmxzcnvz,xcmnvkjdfhgusidktyiuer7y69854376598043769083769843576rewojutglkdfghj,cjnbm,ncvnbx,m"
    stressString += stressString for i in [0...15] 
    console.log "Stressing Rabbit... #{(stressString.length/1e6).toFixed(2)} MB"
    atmosphere.rainMaker.submit "partsWithoutImages", {name:"stress", data: {values: stressString}, timeout: 10}, (err, report) ->
      console.log "done!", err, report
    atmosphere.rainBucket.listen "partsWithoutImages"
    , (message, headers, deliveryInfo) ->
      console.log "RECEIVED!", deliveryInfo
    , () ->
      console.log "done! 2"


setTimeout () ->
  count()
, 1000

count()
console.log "EOF"