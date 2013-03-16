atmosphere = require "../index"

doJob = (message, headers, deliveryInfo) ->
  console.log "[r] ", message, headers, deliveryInfo
  console.log "[r] ", message.data
  atmosphere.acknowledge "testQ", (err) ->
    if err? then console.log "[e] ack:error", err 
    
atmosphere.connect (err) ->

  console.log "\n\n\n=-=-=[test.connected](1)", err, "\n\n\n"

  if err? then console.log "[e] connect:error", err

  console.log "\n\n\n=-=-=[test.connected](2)", err, "\n\n\n"
    
  atmosphere.listenFor "testQ", doJob, (err) ->
    if err? then console.log "[e] listenFor:error", err

  atmosphere.submit "testQ", "Hello World!", (err) ->
    if err? then console.log "[e] submit:error", err
    console.log "[t] Job submitted"

    
