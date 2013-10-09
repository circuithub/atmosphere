StatusCtrl = ($scope) ->
  console.log "\n\n\n=-=-=[STATUS+CTRL]", "yo!", "\n\n\n" #xxx
  # fire.refs().rainCloudsRef.on "value", (snapshot) ->
  #   console.log "\n\n\n=-=-=[StatusCtrl]", "Updating from Firebase", "\n\n\n" #xxx
  #   $scope.rainClouds = snapshot.val()
  $scope.rainCloudID = "Yo dude"
  $scope.rainCloud = "Testing... 123"