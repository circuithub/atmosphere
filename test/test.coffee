atmosphere = require "../index"

atmosphere.connect (err) ->
	if err? then console.log "[e] connect:error", err
		
	atmosphere.listenFor "testQ", doJob, (err) ->
		if err? then console.log "[e] listenFor:error", err

	atmosphere.submit "testQ", "Hello World!", (err) ->
		if err? then console.log "[e] submit:error", err
		console.log "[t] Job submitted"

doJob = (message, headers, deliveryInfo) ->
	console.log "[r] ", message, headers, deliveryInfo
	atmosphere.acknowledge "testQ", (err) ->
		if err? then console.log "[e] ack:error", err			
