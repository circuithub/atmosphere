# src folder
toast "../client/app"

  # excluded items (will be used as a regex)
  exclude: ['.DS_Store' ]

  # packaging vendors among the code
  vendors: ['/x.js', 'vendors/y.js' ]

  # gereral options (all is optional, default values listed)
  bare: false
  packaging: true
  expose: '' # can be 'window', 'exports' etc
  minify: false

  # httpfolder (optional), release and debug (both required)
  httpfolder: 'js'
  release: 'public/app.js'
  debug: 'public/app-debug.js'