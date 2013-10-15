"use strict"

# Load CircuitHub environment variables
nconf = require "nconf"
nconf
  .argv()
  .env()
  .defaults({"NODE_ENV": "development", "APP_DIR": __dirname, "APP_ROOT_URL": "http://localhost:8081/"})
nconf.add("test", {type: "file", file: __dirname + "/configs/test.config.json"})
nconf.add("common", {type: "file", file: __dirname + "/configs/common.config.json"})

# Additional configuration
LIVERELOAD_PORT = 35730
WEBSERVER_PORT = (nconf.get "PORT") ? 3000

module.exports = (grunt) ->
  # Load all grunt plugins
  require("matchdep").filter("grunt-*").forEach grunt.loadNpmTasks
  if (nconf.get "NODE_ENV") == "development"
    require("matchdep").filterDev("grunt-*").forEach grunt.loadNpmTasks

  # Initialize grunt configuration
  grunt.initConfig
    pkg: grunt.file.readJSON "package.json"

    yeoman:
      client: require("./bower.json").appPath
      server: "./server/server"
      dist: "./server/public/dist/"
      fallback: "./server/public"

    watch:
      options:
        nospawn: true
      stylus:
        files: ["<%= yeoman.client %>/{,**/}*.{styl,css}"]
        tasks: ["app:css", "concat:dev"]
        options: livereload: true
      jade:
        files: ["<%= yeoman.client %>/{,**/}*.jade"]
        tasks: ["app:html", "concat:dev"]
        options: livereload: true
      client:
        files: ["<%= yeoman.client %>/{,**/}*!(.unit).coffee"]
        tasks: ["coffee:changed", "concat:dev"]
        options: livereload: true
      clientTest:
        files: ["<%= yeoman.client %>/{,*/}*.unit.coffee"]
        tasks: ["coffee:tests"] # TODO: run client-side tests... (live reload?... karma probably takes care of this)
       server: # this now includes both !(.unit).coffee && .unit.coffee
        files:  ["<%= yeoman.server %>/{,*/}*.coffee"]
        tasks:  ["test:server-background"] # TODO: restart server...?
        onChange: (filepath) ->
          src = filepath.replace /\.[^/]+$/, ".unit.coffee"
          if !grunt.file.exists(src)
            grunt.config "test.server-background.files", []
            return
          dest = filepath.replace /\.[^/]+$/, ".unit.spec"
          grunt.config "test.server-background.files", [{ src: src, dest: dest}]

      livereload:
        options: livereload: LIVERELOAD_PORT
        files: [ "<%= yeoman.dist %>/{,*/}*.*" ]

    express:
      options:
        # Override defaults here
        port: WEBSERVER_PORT
        cmd: "coffee"
      test: options: script: "./server/server.coffee"
      dev: options: script: "./server/server.coffee"
      prod: options:
        script: "./server/server.coffee"
        background: false

    open:
      unittests: url: "http://localhost:8080/" # TODO: rename to clientTests?
      client: url: "http://localhost:<%= express.options.port %>/dashboard"
      #client: url: "http://localhost:<%= connect.options.port %>/new/#/quote"

    clean:
      dist: files: [
        dot: true
        src: [
          ".tmp",
          "<%= yeoman.dist %>/*",
          "!<%= yeoman.dist %>/.git*"
        ]
      ]
      server: ".tmp"

    coffee:
      options:
        bare: true
      dist: files: [
        expand: true
        cwd: "<%= yeoman.client %>/"
        src: "{,**/}*.coffee"
        dest: ".tmp/scripts"
        ext: ".js"
      ]
      testsClient: files: [
        expand: true
        cwd: "<%= yeoman.client %>"
        src: "{,**/}*.unit.coffee"
        dest: ".tmp/spec/unit/client"
        ext: ".js"
      ]
      changed: files: [
        expand: true
        cwd: "<%= yeoman.client %>"
        src: "{,**/}*!(.unit).coffee"
        dest: ".tmp/scripts"
        ext: ".js"
      ]

    stylus:
      options: import: ["nib"]
      dist: files: [
        "<%= yeoman.dist %>/app.css": [".tmp/app.styl"]
      ]

    # stylus: dist: files: [
    #   expand: true
    #   cwd: "<%= yeoman.client %>/"
    #   src: "{,*/}*.styl"
    #   dest: ".tmp/styles"
    #   ext: ".css"
    # ]

    jade:
      dist:
        options: data:
          # TODO: add user info from the current session
          stripePubKey : nconf.get "STRIPE_PUB_KEY"
          mode         : nconf.get "NODE_ENV"
          appName      : nconf.get "APP_NAME"
          version      :
            commit: nconf.get "COMMIT_HASH"
          appNewJsFilePath     : nconf.get "APP_NEW_JS_FILEPATH"
          vendorNewJsFilePath  : nconf.get "VENDOR_NEW_JS_FILEPATH"
          appNewCSSFilePath    : nconf.get "APP_NEW_CSS_FILEPATH"
          vendorNewCSSFilePath : nconf.get "VENDOR_NEW_CSS_FILEPATH"
          bugsnagApiKey        : nconf.get "BUGSNAG_API_KEY"
          user:
            id: -1
            username: "guest"
            email: ""
            avatar: ""
            isModerator: false
          #timestamp: "<%= grunt.template.today() %>"
        files: [
          expand: true
          cwd: "<%= yeoman.client %>/"
          src: "{,**/}*.jade"
          dest: ".tmp/app-templates/"
          ext: ".html"
        ]

    html2js:
      app:
        options: base: ".tmp/app-templates"
        src: [".tmp/app-templates/{,**/}*.html"]
        dest: ".tmp/app-templates.js"

    concat:
      stylus: files: ".tmp/app.styl": ["<%= yeoman.client %>/{,**/}*.{styl,css}"]
      dev: files:
        "<%= yeoman.dist %>/app.js": [
          ".tmp/app-templates.js",
          ".tmp/scripts/{,**/}*.js",
          ".tmp/scripts/*/*.js"
        ]
        "<%= yeoman.dist %>/vendor.js": [
          "angular-latest/build/angular"
          "angular-ui-router/build/angular-ui-router"
          "angular-bootstrap/ui-bootstrap"
          "angular-bootstrap/ui-bootstrap-tpls"
          "angular-sanitize/angular-sanitize"
          "angular-slider/angular-slider"
          "angular-fire/angularFire"
          "json3/lib/json3"
          "lodash/lodash"
        ].map((s) -> "components/#{s}.js").concat [
          ".tmp/vendor-templates.js"
        ]
        "<%= yeoman.dist %>/vendor.css": [
          #"bootstrap/dist/css/bootstrap"
          "bootstrap/dist/css/bootstrap-theme"
          "angular-slider/angular-slider"
        ].map((s) -> "components/#{s}.css")

    karma:
      unit:
        configFile: "karma-client-unit.conf.coffee"
        singleRun: true

    test:
      server: files: [
        expand: true
        cwd: "<%= yeoman.server %>"
        src: "{,*/}*.unit.coffee"
        dest: "<%= yeoman.server %>"
        ext: ".unit.spec"
      ]
      client: tasks: ["karma", "open:unittests"]

    copy: fallback: files: [
      expand: true
      dot: true
      cwd: "components/bootstrap/dist"
      dest: "<%= yeoman.fallback %>"
      src: ["css/bootstrap.css", "fonts/*"]
    ,
      expand: true
      dot: true
      cwd: "components/font-awesome"
      dest: "<%= yeoman.fallback %>"
      src: ["font/*.!(otf)*", "css/font-awesome.css"]
    ]

  grunt.event.on "watch", (action, filepath, target) ->
    cb = grunt.config("watch.#{target}.onChange")
    cb?(filepath)

  grunt.registerTask "prod",      "Run CircuitHub in production mode",
                                  ["express:prod"]
  grunt.registerTask "dev:run",   "Build, test & run CircuitHub in development mode",
                                  #["dev:build", "express:dev", "test:server-background", "test:client", "open:client", "watch"]
                                  #["dev:build", "express:dev", "test:server-background", "open:client", "watch"]
                                  ["dev:build", "express:dev", "open:client", "watch"]
  grunt.registerTask "dev:test",  "Run all CircuitHub tests",
                                  #["dev:build", "test:server", "test:client", "watch"]
                                  ["dev:build", "test:server", "watch"]

  grunt.registerTask "dev:build", "Build the development version of CircuitHub",
                                  ["clean:dist", "app:css", "app:html", "app:js", "tests:js", "concat:dev", "copy:fallback"]

  grunt.registerTask "app:css",   "Generate client (app) css",
                                  ["concat:stylus", "stylus"]
  grunt.registerTask "app:html",  "Generate client (app) html",
                                  ["jade", "html2js"]
  grunt.registerTask "app:js",    "Generate client (app) javascript",
                                  ["coffee:dist"]
  grunt.registerTask "tests:js",  "Generate tests' javascript",
                                  ["coffee:testsClient"]
  grunt.registerTask "default",   ["dev:run"]
  grunt.registerTask "heroku",    "Build CircuitHub on heroku as part of the buildpack",
                                  ["dev:build"] # TODO: build:prod
