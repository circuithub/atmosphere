###
 _______ _______ _______  _____  _______  _____  _     _ _______  ______ _______
 |_____|    |    |  |  | |     | |______ |_____] |_____| |______ |_____/ |______
 |     |    |    |  |  | |_____| ______| |       |     | |______ |    \_ |______

###

#Set ENV var CLOUD_ID on atmosphere.raincloud servers

###
1. worker functions in rain cloud apps get called like this:
  your_function(ticket, jobData)
2. When done, call doneWith(..) and give the ticket back along with any response data (must serialize to JSON)...
  atmosphere.thunder ticket, responseData
###

exports.rainCloud = require "./lib/rain.cloud"
exports.rainMaker = require "./lib/rain.maker"
exports.rainBucket = require "./lib/rain.bucket"
