_          = require "underscore"
should     = require "should"
atmosphere = require "../index"
bsync      = require "bsync"
h          = require "./helpers"
Firebase   = require "firebase"
nconf      = require "nconf"

nconf.env()

console.log "\n\n\n=-=-=[START]", "Make sure that './test/test.rain.cloud' is running..."
console.log "=-=-=[START]", "Make sure that 'coffee server.coffee' is running..."

###############################
## RUN ME! Yay! Tests!

console.log "\n\n\n=-=-=[rain.maker]", nconf.get("FIREBASE_URL"), "\n\n\n" #xxx

atmosphere.rainMaker.init "swarmGenerator", nconf.get("FIREBASE_URL"), undefined, (error) ->
  testFunctions = []
  for i in [0...200]
    switch i % 3
      when 0
        testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "first", name: "loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
      when 1
        testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "second", name: "loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
      when 2
        testFunctions.push bsync.apply atmosphere.rainMaker.submit, {type: "third", name: "loop#{i}", data: {jobID: i, a:"hi",b:"world"}, timeout: 60}
  bsync.parallel testFunctions, (allErrors, allResults) ->