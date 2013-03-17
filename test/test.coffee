atmosphere = require "../index"

doJob = (message, headers, deliveryInfo) ->
  console.log "[r] ", message, headers, deliveryInfo
  atmosphere.acknowledge deliveryInfo.queue, (err) ->
    if err? then console.log "[e] ack:error", err 
    console.log "[a] Acknowledge #{deliveryInfo.queue}"
    if message.typeResponse?
      atmosphere.submit message.typeResponse, "Received!", (err) ->
        if err? then console.log "[e] submitResp:error", err 
        console.log "[t] Response submitted to #{message.typeResponse}"
        
    
atmosphere.connect (err) ->
  if err? then console.log "[e] connect:error", err
    
  atmosphere.listenFor "testQ", doJob, (err) ->
    if err? then console.log "[e] listenFor:error", err
    console.log "[L] Listening to testQ"

  # atmosphere.submit "testQ", {test: "Hello World!"}, (err) ->
  #   if err? then console.log "[e] submit:error", err
  #   console.log "[t] Job submitted"

  # atmosphere.submitFor "testQ", "respQ", {a:"hi",b:"mir"}, doJob, (err) ->
  #   if err? then console.log "[e] submit:error", err
  #   console.log "[t] Job submitted for response"


    
