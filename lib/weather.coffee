core = require "./core"

weather = undefined

exports.pattern = (cbLoaded) ->
  if weather?
    cbLoaded undefined, weather
    return
  #[1.] Load Task List
  atmosphere.core.refs().weatherRef.once "value", (snapshot) ->
    #[2.] Retrieved Weather Pattern
    weather = snapshot.val()
    cbLoaded undefined, weather