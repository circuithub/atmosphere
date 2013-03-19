atmosphere = require "../index"

###############################
## RAINCLOUD Config

altiumCounter = 0

workerDoAltium = (data) ->
  console.log "[W] ALTIUM", data 
  altiumCounter++
  atmosphere.thunder {result:"Done with Altium", count: altiumCounter}

workerDoOrCAD = (data) ->
  console.log "[W] ORCAD", data
  atmosphere.thunder "Done with ORCAD job"

jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
}



###############################
## RUN ME! Yay! Tests!

#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.init.rainCloud jobTypes, (err) ->
  console.log "[I] Initialized RAINCLOUD", err
  #Init Rainmaker (App Server)
  atmosphere.init.rainMaker (err) ->
    console.log "[I] Initialized RAINMAKER", err

    #Submit Altium Conversion Job
    atmosphere.submitFor "convertAltium", {name: "altium-job1", data: {a:"hi",b:"world"}, timeout: 15}, (err, data) ->
      console.log "[D] Job Done", err, data

console.log "EOF"