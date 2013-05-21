Mocha         = require "mocha"

process.setMaxListeners 100 #mute mem-leak warning

do ->
  task "test", "Run the atmosphere test suite", ->
    files = ["./test/test.coffee"]
    mocha = new Mocha
      ui: "bdd"
      ignoreLeaks: true
      growl: true
      timeout: 80000
    mocha.reporter "spec"  
    for file in files
      mocha.addFile file
    mocha.run (failures) =>
      process.exit(failures)
