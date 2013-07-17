core = require "./core"

weather = undefined

exports.pattern = (cbLoaded) ->
  if weather?
    cbLoaded undefined, weather
    return
  core.refs().weatherRef.once "value", (snapshot) ->
    weather = snapshot.val()
    cbLoaded undefined, weather