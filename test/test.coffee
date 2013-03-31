atmosphere = require "../index"

###############################
## RAINCLOUD Config

altiumCounter = 0

workerDoAltium = (ticket, data) ->
  console.log "[W] ALTIUM", ticket, data 
  altiumCounter++
  atmosphere.doneWith ticket, {result:"Done with Altium", count: altiumCounter}

workerDoOrCAD = (ticket, data) ->
  console.log "[W] ORCAD", ticket, data
  atmosphere.doneWith ticket, "Done with ORCAD job"

jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
}

withTester = (ticket, data) ->
  console.log "[Ww] Listen/Submit With Tester", ticket, data

###############################
## RUN ME! Yay! Tests!

#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.init.rainCloud jobTypes, (err) ->
  console.log "[I] Initialized RAINCLOUD", err
  
  #Init Rainmaker (App Server)
  atmosphere.init.rainMaker (err) ->
    console.log "[I] Initialized RAINMAKER", err

    #Submit Altium Conversion Job
    atmosphere.submitFor "convertAltium", {name: "job-altium1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}, (err, data) ->
      console.log "[D] Job Done", err, data

    #Submit Altium Conversion Job
    atmosphere.submitFor "convertOrCAD", {name: "job-orcad1", data: {jobID: "1", a:"hi",b:"world"}, timeout: 60}, (err, data) ->
      console.log "[D] Job Done", err, data

    for i in [0...10]
      #Submit Altium Conversion Job
      atmosphere.submitFor "convertAltium", {name: "job-altium-loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}, (err, data) ->
        console.log "[D] Job Done", err, data

    #Test ...With functions
    atmosphere.listenWith "testSubmitWith", withTester, (err) ->
      atmosphere.submitWith "testSubmitWith", {type: "testSubmitWith", job: {name: "first-test", id: 42}}, "DATA!", (err) ->
        console.log "[Sw] Submitted.", err

console.log "EOF"