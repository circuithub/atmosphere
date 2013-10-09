describe('state', function () {

  var locationProvider, templateParams;

  beforeEach(module('ui.router', function($locationProvider) {
    locationProvider = $locationProvider;
    $locationProvider.html5Mode(false);
  }));

  var log, logEvents, logEnterExit;
  function eventLogger(event, to, toParams, from, fromParams) {
    if (logEvents) log += event.name + '(' + to.name + ',' + from.name + ');';
  }
  function callbackLogger(what) {
    return function () {
      if (logEnterExit) log += this.name + '.' + what + ';';
    };
  }

  var A = { data: {} },
      B = {},
      C = {},
      D = { params: [ 'x', 'y' ] },
      DD = { parent: D, params: [ 'x', 'y', 'z' ] },
      E = { params: [ 'i' ] },
      H = { data: {propA: 'propA', propB: 'propB'} },
      HH = { parent: H },
      HHH = {parent: HH, data: {propA: 'overriddenA', propC: 'propC'} }
      AppInjectable = {};

  beforeEach(module(function ($stateProvider, $provide) {
    angular.forEach([ A, B, C, D, DD, E, H, HH, HHH ], function (state) {
      state.onEnter = callbackLogger('onEnter');
      state.onExit = callbackLogger('onExit');
    });

    $stateProvider
      .state('A', A)
      .state('B', B)
      .state('C', C)
      .state('D', D)
      .state('DD', DD)
      .state('E', E)
      .state('H', H)
      .state('HH', HH)
      .state('HHH', HHH)

      .state('home', { url: "/" })
      .state('home.item', { url: "front/:id" })
      .state('about', { url: "/about" })
      .state('about.person', { url: "/:person" })
      .state('about.person.item', { url: "/:id" })
      .state('about.sidebar', {})
      .state('about.sidebar.item', {
        url: "/:item",
        templateUrl: function(params) {
          templateParams = params;
          return "/templates/" + params.item + ".html";
        }
      });

    $provide.value('AppInjectable', AppInjectable);
  }));

  beforeEach(inject(function ($rootScope) {
    log = '';
    logEvents = logEnterExit = false;
    $rootScope.$on('$stateChangeStart', eventLogger);
    $rootScope.$on('$stateChangeSuccess', eventLogger);
    $rootScope.$on('$stateChangeError', eventLogger);
  }));


  function $get(what) {
    return jasmine.getEnv().currentSpec.$injector.get(what);
  }

  function initStateTo(state, optionalParams) {
    var $state = $get('$state'), $q = $get('$q');
    $state.transitionTo(state, optionalParams || {});
    $q.flush();
    expect($state.current).toBe(state);
  }


  describe('.transitionTo()', function () {
    it('returns a promise for the target state', inject(function ($state, $q) {
      var trans = $state.transitionTo(A, {});
      $q.flush();
      expect(resolvedValue(trans)).toBe(A);
    }));

    it('allows transitions by name', inject(function ($state, $q) {
      $state.transitionTo('A', {});
      $q.flush();
      expect($state.current).toBe(A);
    }));

    it('ignores non-applicable state parameters', inject(function ($state, $q) {
      $state.transitionTo('A', { w00t: 'hi mom!' });
      $q.flush();
      expect($state.current).toBe(A);
    }));

    it('triggers $stateChangeStart', inject(function ($state, $q, $rootScope) {
      initStateTo(E, { i: 'iii' });
      var called;
      $rootScope.$on('$stateChangeStart', function (ev, to, toParams, from, fromParams) {
        expect(from).toBe(E);
        expect(fromParams).toEqual({ i: 'iii' });
        expect(to).toBe(D);
        expect(toParams).toEqual({ x: '1', y: '2' });

        expect($state.current).toBe(from); // $state not updated yet
        expect($state.params).toEqual(fromParams);
        called = true;
      });
      $state.transitionTo(D, { x: '1', y: '2' });
      $q.flush();
      expect(called).toBeTruthy();
      expect($state.current).toBe(D);
    }));

    it('can be cancelled by preventDefault() in $stateChangeStart', inject(function ($state, $q, $rootScope) {
      initStateTo(A);
      var called;
      $rootScope.$on('$stateChangeStart', function (ev) {
        ev.preventDefault();
        called = true;
      });
      var promise = $state.transitionTo(B, {});
      $q.flush();
      expect(called).toBeTruthy();
      expect($state.current).toBe(A);
      expect(resolvedError(promise)).toBeTruthy();
    }));

    it('triggers $stateChangeSuccess', inject(function ($state, $q, $rootScope) {
      initStateTo(E, { i: 'iii' });
      var called;
      $rootScope.$on('$stateChangeSuccess', function (ev, to, toParams, from, fromParams) {
        expect(from).toBe(E);
        expect(fromParams).toEqual({ i: 'iii' });
        expect(to).toBe(D);
        expect(toParams).toEqual({ x: '1', y: '2' });

        expect($state.current).toBe(to); // $state has been updated
        expect($state.params).toEqual(toParams);
        called = true;
      });
      $state.transitionTo(D, { x: '1', y: '2' });
      $q.flush();
      expect(called).toBeTruthy();
      expect($state.current).toBe(D);
    }));

    it('is a no-op when passing the current state and identical parameters', inject(function ($state, $q) {
      initStateTo(A);
      var trans = $state.transitionTo(A, {}); // no-op
      expect(trans).toBeDefined(); // but we still get a valid promise
      $q.flush();
      expect(resolvedValue(trans)).toBe(A);
      expect($state.current).toBe(A);
      expect(log).toBe('');
    }));

    it('aborts pending transitions (last call wins)', inject(function ($state, $q) {
      initStateTo(A);
      logEvents = true;

      var superseded = $state.transitionTo(B, {});
      $state.transitionTo(C, {});
      $q.flush();
      expect($state.current).toBe(C);
      expect(resolvedError(superseded)).toBeTruthy();
      expect(log).toBe(
        '$stateChangeStart(B,A);' +
        '$stateChangeStart(C,A);' +
        '$stateChangeSuccess(C,A);');
    }));

    it('aborts pending transitions even when going back to the current state', inject(function ($state, $q) {
      initStateTo(A);
      logEvents = true;

      var superseded = $state.transitionTo(B, {});
      $state.transitionTo(A, {});
      $q.flush();
      expect($state.current).toBe(A);
      expect(resolvedError(superseded)).toBeTruthy();
      expect(log).toBe(
        '$stateChangeStart(B,A);');
    }));

    it('triggers onEnter and onExit callbacks', inject(function ($state, $q) {
      initStateTo(A);
      logEnterExit = true;
      $state.transitionTo(D, {}); $q.flush();
      log += $state.current.name + ';';
      $state.transitionTo(DD, {}); $q.flush();
      log += $state.current.name + ';';
      $state.transitionTo(A, {}); $q.flush();
      expect(log).toBe(
        'A.onExit;' +
        'D.onEnter;' +
        'D;' +
        'DD.onEnter;' +
        'DD;' +
        'DD.onExit;' +
        'D.onExit;' +
        'A.onEnter;');
    }));

    it('doesn\'t transition to parent state when child has no URL', inject(function ($state, $q) {
      $state.transitionTo('about.sidebar'); $q.flush();
      expect($state.current.name).toEqual('about.sidebar');
    }));
  });

  describe('.go()', function () {
    it('transitions to a relative state', inject(function ($state, $q) {
      $state.transitionTo('about.person.item', { id: 5 }); $q.flush();
      $state.go('^.^.sidebar'); $q.flush();
      expect($state.$current.name).toBe('about.sidebar');

      // Transitions to absolute state
      $state.go("home"); $q.flush();
      expect($state.$current.name).toBe('home');


      // Transition to a child state
      $state.go(".item", { id: 5 }); $q.flush();
      expect($state.$current.name).toBe('home.item');

      // Transition to grandparent's sibling through root
      // (Equivalent to absolute transition, assuming the root is known).
      $state.go("^.^.about"); $q.flush();
      expect($state.$current.name).toBe('about');

      // Transition to grandchild
      $state.go(".person.item", { person: "bob", id: 13 }); $q.flush();
      expect($state.$current.name).toBe('about.person.item');

      // Transition to immediate parent
      $state.go("^"); $q.flush();
      expect($state.$current.name).toBe('about.person');

      // Transition to sibling
      $state.go("^.sidebar"); $q.flush();
      expect($state.$current.name).toBe('about.sidebar');
    }));

    it('keeps parameters from common ancestor states', inject(function ($state, $stateParams, $q) {
      $state.transitionTo('about.person', { person: 'bob' });
      $q.flush();

      $state.go('.item', { id: 5 });
      $q.flush();

      expect($state.$current.name).toBe('about.person.item');
      expect($stateParams).toEqual({ person: 'bob', id: '5' });

      $state.go('^.^.sidebar');
      $q.flush();
      expect($state.$current.name).toBe('about.sidebar');
    }));
  });

  describe('.is()', function () {
    it('should return true when the current state is passed', inject(function ($state, $q) {
      $state.transitionTo(A); $q.flush();
      expect($state.is(A)).toBe(true);
      expect($state.is('A')).toBe(true);
      expect($state.is(B)).toBe(false);
    }));

    it('should return undefined when queried state does not exist', inject(function ($state) {
      expect($state.is('Z')).toBeUndefined();
    }));
  });

  describe('.includes()', function () {
    it('should return true when the current state is passed', inject(function ($state, $q) {
      $state.transitionTo(A); $q.flush();
      expect($state.includes(A)).toBe(true);
      expect($state.includes('A')).toBe(true);
      expect($state.includes(B)).toBe(false);
    }));

    it('should return true when the current state\'s parent is passed', inject(function ($state, $q) {
      $state.transitionTo('about.person.item'); $q.flush();
      expect($state.includes('about')).toBe(true);
      expect($state.includes('about.person')).toBe(true);
      expect($state.includes('about.sidebar')).toBe(false);
    }));

    it('should return undefined when queried state does not exist', inject(function ($state) {
      expect($state.is('Z')).toBeUndefined();
    }));
  });

  describe('.current', function () {
    it('is always defined', inject(function ($state) {
      expect($state.current).toBeDefined();
    }));

    it('updates asynchronously as the transitionTo() promise is resolved', inject(function ($state, $q) {
      var trans = $state.transitionTo(A, {});
      expect($state.current).not.toBe(A);
      $q.flush();
      expect($state.current).toBe(A);
    }));
  });


  describe('$current', function () {
    it('is always defined', inject(function ($state) {
      expect($state.$current).toBeDefined();
    }));

    it('wraps the raw state object', inject(function ($state) {
      initStateTo(A);
      expect($state.$current.data).toBe(A.data); // 'data' is reserved for app use
    }));
  });


  describe('.params', function () {
    it('is always defined', inject(function ($state) {
      expect($state.params).toBeDefined();
      expect(angular.isObject($state.params)).toBe(true);
    }));

    it('contains the parameter values for the current state', inject(function ($state, $q) {
      initStateTo(D, { x: 'x value', z: 'invalid value' });
      expect($state.params).toEqual({ x: 'x value', y: null });
    }));
  });


  describe('.transition', function () {
    it('is null when no transition is taking place', inject(function ($state, $q) {
      expect($state.transition).toBeNull();
      $state.transitionTo(A, {});
      $q.flush();
      expect($state.transition).toBeNull();
    }));

    it('is the current transition', inject(function ($state, $q) {
      var trans = $state.transitionTo(A, {});
      expect($state.transition).toBe(trans);
    }));
  });


  describe('.href()', function () {
    it('aborts on un-navigable states', inject(function ($state) {
      expect($state.href("A")).toBeNull();
      expect($state.href("about.sidebar", null, { lossy: false })).toBeNull();
    }));

    it('generates a parent state URL when lossy is true', inject(function ($state) {
      expect($state.href("about.sidebar", null, { lossy: true })).toEqual("#/about");
    }));

    it('generates a URL without parameters', inject(function ($state) {
      expect($state.href("home")).toEqual("#/");
      expect($state.href("about", {})).toEqual("#/about");
      expect($state.href("about", { foo: "bar" })).toEqual("#/about");
    }));

    it('generates a URL with parameters', inject(function ($state) {
      expect($state.href("about.person", { person: "bob" })).toEqual("#/about/bob");
      expect($state.href("about.person.item", { person: "bob", id: null })).toEqual("#/about/bob/");
    }));
  });

  describe('.get()', function () {
    it("should return the state's config", inject(function ($state) {
      expect($state.get('home').url).toBe('/');
      expect($state.get('home.item').url).toBe('front/:id');
      expect($state.get('A')).toBe(A);
      expect($state.get('Z')).toBeNull();
    }));
  });

  describe(' "data" property inheritance/override', function () {
    it('"data" property should stay immutable for if state doesn\'t have parent', inject(function ($state) {
      initStateTo(H);
      expect($state.current.name).toEqual('H');
      expect($state.current.data.propA).toEqual(H.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
    }));

    it('"data" property should be inherited from parent if state doesn\'t define it', inject(function ($state) {
      initStateTo(HH);
      expect($state.current.name).toEqual('HH');
      expect($state.current.data.propA).toEqual(H.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
    }));

    it('"data" property should be overridden/extended if state defines it', inject(function ($state) {
      initStateTo(HHH);
      expect($state.current.name).toEqual('HHH');
      expect($state.current.data.propA).toEqual(HHH.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
      expect($state.current.data.propB).toEqual(HH.data.propB);
      expect($state.current.data.propC).toEqual(HHH.data.propC);
    }));
  });

  describe('html5Mode compatibility', function() {

    it('should generate non-hashbang URLs in HTML5 mode', inject(function ($state) {
      expect($state.href("about.person", { person: "bob" })).toEqual("#/about/bob");
      locationProvider.html5Mode(true);
      expect($state.href("about.person", { person: "bob" })).toEqual("/about/bob");
    }));
  });

  describe('url handling', function () {

    it('should transition to the same state with different parameters', inject(function ($state, $rootScope, $location) {
      $location.path("/about/bob");
      $rootScope.$broadcast("$locationChangeSuccess");
      $rootScope.$apply();
      expect($state.params).toEqual({ person: "bob" });

      $location.path("/about/larry");
      $rootScope.$broadcast("$locationChangeSuccess");
      $rootScope.$apply();
      expect($state.params).toEqual({ person: "larry" });
    }));
  });

  describe('default properties', function() {
    it('should always have a name', inject(function ($state, $q) {
      $state.transitionTo(A);
      $q.flush();
      expect($state.$current.name).toBe('A');
      expect($state.$current.toString()).toBe('A');
    }));

    it('should always have a resolve object', inject(function ($state) {
      expect($state.$current.resolve).toEqual({});
    }));
  });

  describe(' "data" property inheritance/override', function () {
    it('"data" property should stay immutable for if state doesn\'t have parent', inject(function ($state) {
      initStateTo(H);
      expect($state.current.name).toEqual('H');
      expect($state.current.data.propA).toEqual(H.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
    }));

    it('"data" property should be inherited from parent if state doesn\'t define it', inject(function ($state) {
      initStateTo(HH);
      expect($state.current.name).toEqual('HH');
      expect($state.current.data.propA).toEqual(H.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
    }));

    it('"data" property should be overridden/extended if state defines it', inject(function ($state) {
      initStateTo(HHH);
      expect($state.current.name).toEqual('HHH');
      expect($state.current.data.propA).toEqual(HHH.data.propA);
      expect($state.current.data.propB).toEqual(H.data.propB);
      expect($state.current.data.propB).toEqual(HH.data.propB);
      expect($state.current.data.propC).toEqual(HHH.data.propC);
    }));
  });

  describe('html5Mode compatibility', function() {

    it('should generate non-hashbang URLs in HTML5 mode', inject(function ($state) {
      expect($state.href("about.person", { person: "bob" })).toEqual("#/about/bob");
      locationProvider.html5Mode(true);
      expect($state.href("about.person", { person: "bob" })).toEqual("/about/bob");
    }));
  });

  describe('default properties', function () {
    it('should always have a name', inject(function ($state, $q) {
      $state.transitionTo(A); $q.flush();
      expect($state.$current.name).toBe('A');
      expect($state.$current.toString()).toBe('A');
    }));

    it('should always have a resolve object', inject(function ($state) {
      expect($state.$current.resolve).toEqual({});
    }));

    it('should include itself and parent states', inject(function ($state, $q) {
      $state.transitionTo(DD); $q.flush();
      expect($state.$current.includes).toEqual({ '': true, D: true, DD: true });
    }));
  });

  describe('template handling', function () {
    it('should inject $stateParams into templateUrl function', inject(function ($state, $q, $httpBackend) {
      $httpBackend.expectGET("/templates/foo.html").respond("200");
      $state.transitionTo('about.sidebar.item', { item: "foo" }); $q.flush();
      expect(templateParams).toEqual({ item: "foo" });
    }));
  });
});
