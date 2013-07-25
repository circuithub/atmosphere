Firebase                = require "firebase"
FirebaseTokenGenerator  = require "firebase-token-generator"

moment = require "moment"
nconf = require "nconf"

firebaseServer = nconf.get "FIREBASE_URL"
firebaseSyncRoot = "/sync"

ready = false # Note: this mechanism isn't used at present, but might be required in future due to changes in firebase library. Currently unauthenticated requests just print warning to console and continue.

###
 Realtime interactions with the user
 -- currently built on Firebase

running = true/false
started = date
stopped = date
ready = true/false -- are we idle?

/users/<user>/sync/status = "..."
/users/<user>/sync/todo
   /<type>/<creator>/<name> = example: symbol/DrFriedParts/d6hhy
   (handles de-dup)
/users/<user>/sync/waiting
   /<type>/<creator>/<name> = example: symbol/DrFriedParts/d6hhy
   (handles de-dup)
###



###
  Generate the firebase data path for sync messaging to the specified user
###
firebasePath = (username) -> 
  return firebaseServer + "/users/#{username}" + firebaseSyncRoot

###
  Authenticate (login) this server with Firebase
  -- cbAuthenticated: (error) ->
    error -- login error (auth failed)
###
exports.init = (cbAuthenticated) =>
  dataRef = new Firebase firebaseServer
  firebaseServerToken = @generateServerToken()
  if firebaseServer.toLowerCase().indexOf("-demo") isnt -1 #Skip authenication if using Firebase demo mode
    console.log "[firebaseAuth]", "Running in demo mode (skipping authenication)"
    ready = true
    cbAuthenticated undefined
    return
  dataRef.auth firebaseServerToken, (error) ->
    ready = true if not error?
    cbAuthenticated error

###
  Generate Access Token for Server
  -- Full access! Be careful!
###
exports.generateServerToken = () ->
  return nconf.get "FIREBASE_SECRET"

###
  Generate Access Token for User
  -- Disable security if user is CircuitHub Admin (can see everything in forge)
###
exports.generateUserToken = (user) ->
  secret = nconf.get "FIREBASE_SECRET"
  tokenGenerator = new FirebaseTokenGenerator secret
  token = tokenGenerator.createToken {}, options
  return token

###
  Send the corresponding Firebase server to the client
###
exports.getServer = () ->
  return firebaseServer
 