Firebase                = require "firebase"
FirebaseTokenGenerator  = require "firebase-token-generator"

nconf = require "nconf"

firebaseServer = nconf.get "FIREBASE_URL"
firebaseSyncRoot = "/sync"

ready = false # Note: this mechanism isn't used at present, but might be required in future due to changes in firebase library. Currently unauthenticated requests just print warning to console and continue.

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
  token = tokenGenerator.createToken {}
  return token

###
  Send the corresponding Firebase server to the client
###
exports.getServer = () ->
  return firebaseServer
 