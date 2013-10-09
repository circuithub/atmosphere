atmosphereModule = angular.module "atmosphere", []

atmosphereModule.factory "fire", ["$window", (win) ->
  msgs = []
  (msg) ->
    msgs.push msg
    if msgs.length is 3
      win.alert msgs.join("\n")
      msgs = []
]

###
  Perform AJAX HTTP GET request (sans jQuery)
###
ajax = (url, cbResponse) ->
  xmlhttp = new XMLHttpRequest()
  xmlhttp.onreadystatechange = () ->
    if xmlhttp.readyState is 4 and xmlhttp.status is 200
      cbResponse undefined, JSON.parse xmlhttp.responseText
      return
    else
      cbResponse "Error", xmlhttp.readyState, xmlhttp.status
      return
  xmlhttp.open "GET", url, true
  xmlhttp.send()

###
  Firebase access encapsulation
###
class _fire
  
  dataRef = undefined
  firebaseToken = undefined
  firebaseServer = undefined
  newToken = true

  _refs = {}

  init: () =>
    start = (next) ->
      if not firebaseToken? or not firebaseServer?
        token next
        return
      next()
    token = (next) ->
      url = "/auth/firebase"
      url += "?n=1" if newToken
      ajax url, (error, res) ->
        if error?
          console.log "[firebaseAuthError]", error
          return
        firebaseToken = res.token
        firebaseServer = res.server
        console.log "\n\n\n=-=-=[fire.init]", res, firebaseServer, firebaseToken, "\n\n\n" #xxx
        next()
    connect = (next) ->
      dataRef = new Firebase "#{firebaseServer}"    
      if firebaseServer.toLowerCase().indexOf("-demo") isnt -1 #Skip authenication if using Firebase demo mode
        console.log "[firebaseAuth]", "Running in demo mode (skipping authenication)"
        next()
        return
      dataRef.auth firebaseToken, (error) ->
        if error?
          if error.code is "EXPIRED_TOKEN"
            console.log "[firebaseAuthError]", "EXPIRED_TOKEN Reconnecting..."
            newToken = true
            token connect
            return
          else
            console.log "[firebaseAuthError]", "Login failed!", error
            return
        next()
    listen = () =>
      _refs.baseRef = dataRef
      _refs.rainGaugeRef = dataRef.child "rainGauge"
      _refs.rainDropsRef = dataRef.child "rainDrops"
      return
    start -> connect -> listen()

  refs: () -> _refs

###
  Connect to Firebase
###
fire = new _fire
fire.init()