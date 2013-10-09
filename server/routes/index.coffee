sky   = require "../services/sky"
fire  = require "../services/fire"
nconf = require "nconf"
_     = require "lodash"
jade = require "jade"



exports.loadRoutes = (app, passport) ->

  auth = (req, res, next) ->
    if req.isAuthenticated and req.isAuthenticated()
      next()
    else
      res.redirect "/"

  app.get "/status", auth, (req, res) ->
    res.setHeader "Content-Type", "application/json"
    res.write "{a:'blahmooquack', b:'hello world'}"
    res.end

  # GET /auth/github
  #   Use passport.authenticate() as route middleware to authenticate the
  #   request.  The first step in GitHub authentication will involve redirecting
  #   the user to github.com.  After authorization, GitHub will redirect the user
  #   back to this application at /auth/github/callback
  app.get "/auth/github", passport.authenticate("github"), (req, res) ->
    # The request will be redirected to GitHub for authentication, so this
    # function will not be called.

  # GET /auth/github/callback
  #   Use passport.authenticate() as route middleware to authenticate the
  #   request.  If authentication fails, the user will be redirected back to the
  #   login page.  Otherwise, the primary route function function will be called,
  #   which, in this example, will redirect the user to the home page.
  app.get "/auth/github/callback",
    passport.authenticate("github", { failureRedirect: "/" }),
    (req, res) ->
      console.log "\n\n\n=-=-=[github response]", res, "\n\n\n" #xxx
      res.redirect "/"

  ###
    GET Authentication token for Firebase
  ###
  app.get "/auth/firebase", auth, (req, res) ->
    #update Firebase token if n query parameter (new) is specified
    if req.query.n?
      req.session.user ?= {}
      req.session.user.firebaseToken = fire.generateUserToken req.session.user
    res.setHeader "Content-Type", "application/json"
    res.send {token: req.session.user.firebaseToken, server: fire.getServer()}

  ###
    GET Logout
  ###
  app.get "/logout", (req, res) ->
    req.logout()
    res.redirect "/"

  # Set up local variables to use for rendering
  appLocals =
    mode              : nconf.get "NODE_ENV"
    appName           : nconf.get "APP_NAME"
    version           : commit : nconf.get "COMMIT_HASH"
    appJsFilePath     : nconf.get "APP_JS_FILEPATH"
    vendorJsFilePath  : nconf.get "VENDOR_JS_FILEPATH"
    appCSSFilePath    : nconf.get "APP_CSS_FILEPATH"
    vendorCSSFilePath : nconf.get "VENDOR_CSS_FILEPATH"

  # AngularJS routes
  appRoutes = [
    "/dashboard"
  ]

  # Render application page => single page application.
  for route in appRoutes
    ### GET single page app routes ###
    app.get route, auth, (req, res) ->
      options = _.extend {
          cache: true
          user: if req.session.user?.id then req.session.user
        }, appLocals
      res.render("index", options)
      #jade.renderFile "#{__dirname}/../../client/app/dashboard/dashboard.jade", options, (error, html) -> res.send html

