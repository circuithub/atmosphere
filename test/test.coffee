atmosphere = require "../index"

doJob = (message, headers, deliveryInfo) ->
  console.log "[r] ", message, headers, deliveryInfo
  atmosphere.acknowledge "testQ", (err) ->
    if err? then console.log "[e] ack:error", err 
    console.log "[a] Acknowledge"
    if message.typeResponse?
      atmosphere.submit message.typeResponse, "Received!", (err) ->
        if err? then console.log "[e] submitResp:error", err 
        console.log "[t] Response submitted"
        
    
atmosphere.connect (err) ->

  console.log "\n\n\n=-=-=[test.connected](1)", err, "\n\n\n"

  if err? then console.log "[e] connect:error", err

  console.log "\n\n\n=-=-=[test.connected](2)", err, "\n\n\n"
    
  atmosphere.listenFor "testQ", doJob, (err) ->
    if err? then console.log "[e] listenFor:error", err

  atmosphere.submit "testQ", '{test: "Hello World!"}', (err) ->
    if err? then console.log "[e] submit:error", err
    console.log "[t] Job submitted"

  atmosphere.submitFor "testQ", "respQ", {a:"hi",b:"mir"}, doJob, (err) ->
    if err? then console.log "[e] submit:error", err
    console.log "[t] Job submitted for response"


    
