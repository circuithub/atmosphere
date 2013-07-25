# src folder
toast "app"

  # excluded items (will be used as a regex)
  exclude: [".DS_Store"]

  # packaging vendors among the code
  vendors: [
    "../vendors/angularfire.min.js"
    "../vendors/jquery-1.9.1.min.js"
    "../vendors/moment.js" 
  ]

  # gereral options (all is optional, default values listed)
  bare: false
  packaging: true
  expose: '' # can be 'window', 'exports' etc
  minify: false

  # httpfolder (optional), release and debug (both required)
  release: '../server/public/app.js'
  debug: '../server/public/app-debug.js'