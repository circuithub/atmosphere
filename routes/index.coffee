sky = require "../services/sky"

exports.loadRoutes = (app, passport) ->

  auth = (req, res, next) ->
    if req.isAuthenticated and req.isAuthenticated()
      next()
    else
      res.redirect "/"
    
  ###
    GET Authentication token for Firebase
  ###
  app.get "/auth/firebase", auth, (req, res) ->
    res.setHeader "Content-Type", "application/json"
    res.write "{a:'blahmooquack', b:'hello world'}"
    res.end

  ###
   GET home page.
  ###
  app.get "/dashboard", auth, (req, res) ->
    res.render 'dashboard', 
      title: "Spark by CircuitHub"
      dashboard: sky.dashboard()

  app.get "/status", auth, (req, res) ->
    res.setHeader "Content-Type", "application/json"
    res.write "{a:'blahmooquack', b:'hello world'}"
    res.end

  # GET /auth/github
  #   Use passport.authenticate() as route middleware to authenticate the
  #   request.  The first step in GitHub authentication will involve redirecting
  #   the user to github.com.  After authorization, GitHub will redirect the user
  #   back to this application at /auth/github/callback
  app.get "/auth/github",
    passport.authenticate("github"),
    (req, res) ->
      # The request will be redirected to GitHub for authentication, so this
      # function will not be called.

  # GET /auth/github/callback
  #   Use passport.authenticate() as route middleware to authenticate the
  #   request.  If authentication fails, the user will be redirected back to the
  #   login page.  Otherwise, the primary route function function will be called,
  #   which, in this example, will redirect the user to the home page.
  app.get "/auth/github/callback", 
    passport.authenticate("github", { failureRedirect: "/auth/github" }),
    (req, res) ->
      res.redirect "/dashboard"

  app.get "/logout", (req, res) ->
    req.logout()
    res.redirect "/"
