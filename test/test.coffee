atmosphere = require "../index"

doJob = (message, headers, deliveryInfo) ->
  console.log "[r] ", message, headers, deliveryInfo
  atmosphere.acknowledge deliveryInfo.queue, (err) ->
    if err? then console.log "[e] ack:error", err 
    console.log "[a] Acknowledge #{deliveryInfo.queue}"
    atmosphere.doneWith deliveryInfo.queue, () ->
      console.log "[X] Deleted #{deliveryInfo.queue}"    
      if message.typeResponse?
        atmosphere.submit message.typeResponse, "Received!"
        console.log "[t] Response submitted to #{message.typeResponse}"
          
    
atmosphere.connect (err) ->
  if err? then console.log "[e] connect:error", err
    
  atmosphere.listen "testQ", doJob, (err) ->
    if err? then console.log "[e] listenFor:error", err
    console.log "[L] Listening to testQ"
  
    try
      atmosphere.submit "testQ", {test: "Hello World!"}
      console.log "[t] Job submitted"
    catch e
      console.log "[e] Failure during submit ", e

  # atmosphere.submitFor "testQ", "respQ", {a:"hi",b:"mir"}, doJob, (err) ->
  #   if err? then console.log "[e] submit:error", err
  #   console.log "[t] Job submitted for response"


    
