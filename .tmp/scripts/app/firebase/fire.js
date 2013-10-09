var ajax, atmosphereModule, fire, _fire,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

atmosphereModule = angular.module("atmosphere", []);

atmosphereModule.factory("fire", [
  "$window", function(win) {
    var msgs;
    msgs = [];
    return function(msg) {
      msgs.push(msg);
      if (msgs.length === 3) {
        win.alert(msgs.join("\n"));
        return msgs = [];
      }
    };
  }
]);

/*
  Perform AJAX HTTP GET request (sans jQuery)
*/


ajax = function(url, cbResponse) {
  var xmlhttp;
  xmlhttp = new XMLHttpRequest();
  xmlhttp.onreadystatechange = function() {
    if (xmlhttp.readyState === 4 && xmlhttp.status === 200) {
      cbResponse(void 0, JSON.parse(xmlhttp.responseText));
    } else {
      cbResponse("Error", xmlhttp.readyState, xmlhttp.status);
    }
  };
  xmlhttp.open("GET", url, true);
  return xmlhttp.send();
};

/*
  Firebase access encapsulation
*/


_fire = (function() {
  var dataRef, firebaseServer, firebaseToken, newToken, _refs;

  function _fire() {
    this.init = __bind(this.init, this);
  }

  dataRef = void 0;

  firebaseToken = void 0;

  firebaseServer = void 0;

  newToken = true;

  _refs = {};

  _fire.prototype.init = function() {
    var connect, listen, start, token,
      _this = this;
    start = function(next) {
      if ((firebaseToken == null) || (firebaseServer == null)) {
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
      return ajax(url, function(error, res) {
        if (error != null) {
          console.log("[firebaseAuthError]", error);
          return;
        }
        firebaseToken = res.token;
        firebaseServer = res.server;
        console.log("\n\n\n=-=-=[fire.init]", res, firebaseServer, firebaseToken, "\n\n\n");
        return next();
      });
    };
    connect = function(next) {
      dataRef = new Firebase("" + firebaseServer);
      if (firebaseServer.toLowerCase().indexOf("-demo") !== -1) {
        console.log("[firebaseAuth]", "Running in demo mode (skipping authenication)");
        next();
        return;
      }
      return dataRef.auth(firebaseToken, function(error) {
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
      _refs.baseRef = dataRef;
      _refs.rainGaugeRef = dataRef.child("rainGauge");
      _refs.rainDropsRef = dataRef.child("rainDrops");
    };
    return start(function() {
      return connect(function() {
        return listen();
      });
    });
  };

  _fire.prototype.refs = function() {
    return _refs;
  };

  return _fire;

})();

/*
  Connect to Firebase
*/


fire = new _fire;

fire.init();
