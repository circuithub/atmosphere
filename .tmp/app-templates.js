angular.module('templates-app', ['app/dashboard/controls.html', 'app/dashboard/dashboard.html', 'app/dashboard/drops.html', 'app/dashboard/status.html', 'directives/metrics-graph-time/metrics-graph-time.html']);

angular.module("app/dashboard/controls.html", []).run(["$templateCache", function($templateCache) {
  $templateCache.put("app/dashboard/controls.html",
    "This is the control panel");
}]);

angular.module("app/dashboard/dashboard.html", []).run(["$templateCache", function($templateCache) {
  $templateCache.put("app/dashboard/dashboard.html",
    "<!DOCTYPE html><html ng-app=\"atmosphereWeatherStation\"></html><head><title>Weather Station (Atmosphere)</title><link rel=\"stylesheet\" href=\"//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.2/css/bootstrap-combined.min.css\"><link rel=\"StyleSheet\" href=\"stylesheets/app.css\" type=\"text/css\" media=\"screen\"><script type=\"text/javascript\" src=\"https://cdn.firebase.com/v0/firebase.js\"></script><script type=\"text/javascript\" src=\"https://ajax.googleapis.com/ajax/libs/angularjs/1.0.7/angular.min.js\"></script><script type=\"text/javascript\" src=\"javascripts/vendor.js\"></script><!-- script(type=\"text/javascript\", src=\"javascripts/ui-bootstrap-tpls-0.4.0.min.js\")--><script type=\"text/javascript\" src=\"javascripts/app.js\"></script></head><body><div class=\"header\"><h1>Atmosphere</h1><span class=\"subtitle\">By CircuitHub</span></div><br><div ng-controller=\"TabsDemoCtrl\" class=\"content\">   <tabset><tab heading=\"Status\"> <div ng-controller=\"StatusCtrl\"><p ng-repeat=\"(rainCloudID, rainCloud) in rainClouds\"><h3>{{rainCloudID}}</h3><h4>{{rainCloud}}</h4><br><div metrics-graph-time class=\"boom\"></div></p></div></tab><tab heading=\"Rain Drops (Jobs)\"> Hello World</tab><tab heading=\"Control Panel\"> This is the control panel</tab></tabset></div></body>");
}]);

angular.module("app/dashboard/drops.html", []).run(["$templateCache", function($templateCache) {
  $templateCache.put("app/dashboard/drops.html",
    "Hello World");
}]);

angular.module("app/dashboard/status.html", []).run(["$templateCache", function($templateCache) {
  $templateCache.put("app/dashboard/status.html",
    "<div ng-controller=\"StatusCtrl\"><p ng-repeat=\"(rainCloudID, rainCloud) in rainClouds\"><h3>{{rainCloudID}}</h3><h4>{{rainCloud}}</h4><br/><div metrics-graph-time=\"metrics-graph-time\" class=\"boom\"></div></p></div>");
}]);

angular.module("directives/metrics-graph-time/metrics-graph-time.html", []).run(["$templateCache", function($templateCache) {
  $templateCache.put("directives/metrics-graph-time/metrics-graph-time.html",
    "<p>dev.coffee</p><p>This is a test of template insertion in a directive </p>");
}]);
