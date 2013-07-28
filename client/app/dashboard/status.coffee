StatusCtrl = ($scope) ->
  fire.refs().rainCloudsRef.on "value", (snapshot) ->
    console.log "\n\n\n=-=-=[StatusCtrl]", "Updating from Firebase", "\n\n\n" #xxx
    $scope.rainClouds = snapshot.val()
