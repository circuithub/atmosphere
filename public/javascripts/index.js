/*
  Update time presentation
*/
function updateClock() {
    return $(".date").each(function(index) {
      element = $(this);
      return element.text("..." + moment(element.attr("data")).fromNow());
    });
  };

/* 
  Connect to Firebase
*/
function initData() {
  //AJAX back to server for token
  //Connect
  //Listen for changes
  sparkRef = new Firebase(nconf.get("FIREBASE_URL") + "atmosphere/spark");
  sparkRef.on("value", updateData); 
}

/*
  Update data
*/
function updateData(snapshot) {
  data = snapshot.val()
  //update fields in GUI
}

  
var firebaseToken = void 0;
var firebaseServer = void 0;
var newToken = false;
var connect, _this = this;

function connect() {  
  var listen, start, token;

  start = function(next) {
    if (!(typeof firebaseToken !== "undefined" && firebaseToken !== null) || !(typeof firebaseServer !== "undefined" && firebaseServer !== null)) {
      token(next);
      return;
    }
    return next();
  };

  token = function(next) {
    var url;
    url = "/auth/firebase";
    if (newToken) {
      url += "?n=1";
    }
    return $.ajax(url).done(function(res) {
      var firebaseServer, firebaseToken;
      firebaseToken = res.token;
      firebaseServer = res.server;
      return next();
    }).fail(function(jqXHR, textStatus, errorThrown) {
      console.log("[firebaseAuthError]", textStatus, errorThrown);
    });
  };

  connect = function(next) {
    var dataRef;
    dataRef = new Firebase("" + firebaseServer + "/users/" + username + "/sync");
    if (firebaseServer.toLowerCase().indexOf("-demo") !== -1) {
      console.log("[firebaseAuth]", "Running in demo mode (skipping authenication)");
      next();
      return;
    }
    return dataRef.auth(firebaseToken, function(error) {
      var newToken;
      if (error != null) {
        if (error.code === "EXPIRED_TOKEN") {
          console.log("[firebaseAuthError]", "EXPIRED_TOKEN Reconnecting...");
          newToken = true;
          token(connect);
          return;
        } else {
          console.log("[firebaseAuthError]", "Login failed!", error);
          return;
        }
      }
      return next();
    });
  };
  listen = function() {
    dataRef.on("value", _this._onChange);
    $(".userSyncModule").alert();
  };

  return start(function() {
    return connect(function() {
      return listen();
    });
  });
};

