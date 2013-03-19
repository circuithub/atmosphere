atmosphere = require "../index"

altiumCounter = 0
workerDoAltium = (data) ->
  console.log "[W] ALTIUM", data 
  altiumCounter++
  atmosphere.thunder {result:"Done with Altium", count: altiumCounter}

workerDoOrCAD = (data) ->
  console.log "[W] ORCAD", data
  atmosphere.thunder "Done with ORCAD job"

#Init Rainmaker (App Server)
atmosphere.init.rainMaker () ->
  console.log "[I] Initialized RAINMAKER"

#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.init.rainCloud () ->
  console.log "[I] Initialized RAINCLOUD"

jobTypes = {
  convertAltium: workerDoAltium
  convertOrCAD: workerDoOrCAD
}

