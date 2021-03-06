coffee   = require "coffee-script"
express  = require "express"
http     = require "http"
nconf    = require "nconf"
objects  = require "objects"
urlParse = require("url").parse
_s       = require "underscore.string"
app      = express()
fs = require "fs"
sys = require('sys')
exec = require('child_process').exec;

dirUp = (path) -> _s.strLeftBack path, "/"

#################################
## Environment
#################################

# -- Load System Environment
nconf
  .argv()
  .env()
  .file({file: dirUp(__dirname) + "/configs/" + app.settings.env + ".config.json"})
  .defaults({
    "PORT": 3000
  })

# -- Routes and Services
routes  = require "./routes"
sky     = require "./services/sky"



#################################
## Authentication
#################################

passport       = require "passport"
GitHubStrategy = require("passport-github").Strategy

passport.serializeUser (user, done) -> done null, user
passport.deserializeUser (obj, done) -> done null, obj

github = require "octonode"

console.log nconf.get "GITHUB_CLIENT_ID"
console.log nconf.get "GITHUB_CLIENT_KEY"
console.log nconf.get "GITHUB_CALLBACK_URL"

# Use the GitHubStrategy within Passport.
#   Strategies in Passport require a `verify` function, which accept
#   credentials (in this case, an accessToken, refreshToken, and GitHub
#   profile), and invoke a callback with a user object.
passport.use new GitHubStrategy {
    clientID: nconf.get "GITHUB_CLIENT_ID"
    clientSecret: nconf.get "GITHUB_CLIENT_KEY"
    callbackURL: nconf.get "GITHUB_CALLBACK_URL"
  },
  (accessToken, refreshToken, profile, done) ->
    # asynchronous verification, for effect...
    process.nextTick () ->
      octonode = new github.client accessToken
      circuithubOrg = octonode.org "circuithub"
      circuithubOrg.members (err, members) ->
        console.log members
        console.log profile.username
        if err?
          done null, null
        orgMember = objects.find members, "login", profile.username
        if orgMember?
          done null, profile
        else
          done null, null



#################################
## Express Middleware
#################################

app.use express.logger()
app.use express.cookieParser()
app.set 'views', __dirname + "/views"
app.set 'view engine', 'jade'
app.set "view options", {layout: false}
###
app.use require("stylus").middleware
  serve: true
  force: true
  debug: true
  src: dirUp(__dirname) + "/client/app"
  dest: __dirname + "/public"

console.log "\n\n\n=-=-=[hi]", dirUp(__dirname) + "/client/app/stylesheets", "\n\n\n" #xxx
console.log "\n\n\n=-=-=[world]", __dirname + "/public/stylesheets"
###
app.use express.bodyParser()
# app.use express.methodOverride()
app.use express.session({ secret: "the super secret blahmooquack", key: "spark.sid" })
app.use passport.initialize()
app.use passport.session()
app.use app.router

app.use express.static __dirname + "/public"


app.configure "development", () ->
  app.use express.errorHandler { dumpExceptions: true, showStack: true }

app.configure "production", () ->
  app.use express.errorHandler()



#################################
## Sky (Scheduling/Recovery)
#################################

# sky.init (err) ->
#   if err?
#     throw err
#   console.log "[atmosphere]", "ICONNECT", "Connected to atmosphere at #{sky.server()}."



#################################
## Weather Station (GUI)
#################################

routes.loadRoutes(app, passport)
server = http.createServer app
server.listen nconf.get("PORT"), () ->
  console.log "\n\n-=< Express server listening on port #{server.address().port} in #{app.settings.env} mode >=-\n\n"
