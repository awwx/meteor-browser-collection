// Generated by CoffeeScript 1.6.1
(function() {
  var Steppers, addTest, check, child1_ready, child1_started, insert_four, log, log0, received_steps, reset_steps, setup_test, sql, step_listeners, test_insert, test_persistent, test_remove, test_remove_multiple, test_update, test_update_multiple, wait_for_step, _when,
    __slice = [].slice,
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  if (Meteor.isServer) {
    Meteor.methods({
      log: function() {
        var args;
        args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
        console.log.apply(console, args);
        return null;
      }
    });
  }

  if (!Meteor.isClient) {
    return;
  }

  Meteor.windowtest.numberOfWindowsToOpen(1);

  _when = window.when;

  log0 = function() {
    var args, e, msg;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    if (typeof console !== "undefined" && console !== null) {
      if (typeof console.log === "function") {
        console.log.apply(console, args);
      }
    }
    msg = _.map(args, function(arg) {
      if (_.isString(arg)) {
        return arg;
      } else {
        return JSON.stringify(arg);
      }
    }).join(' ') + "\n";
    $('#log').append(document.createTextNode(msg));
    e = $('#log')[0];
    if (e != null) {
      e.scrollTop = e.scrollHeight;
    }
    Meteor.call.apply(Meteor, ['log'].concat(__slice.call(args), [function(error) {
      if (error != null) {
        return typeof console !== "undefined" && console !== null ? typeof console.log === "function" ? console.log(error) : void 0 : void 0;
      }
    }]));
    return null;
  };

  log = function() {
    var args, _ref;
    args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    if (window.name === 'child1') {
      return (_ref = Meteor.BrowserMsg).send.apply(_ref, ['log', 'child1:'].concat(__slice.call(args)));
    } else {
      return log0.apply(null, ['parent:'].concat(__slice.call(args)));
    }
  };

  step_listeners = {};

  received_steps = [];

  reset_steps = function() {
    step_listeners = {};
    return received_steps = [];
  };

  Meteor.BrowserMsg.listen({
    'test_step': function(to, step) {
      if (to === window.name) {
        if (step_listeners[step] != null) {
          return step_listeners[step].resolve();
        } else {
          return received_steps.push(step);
        }
      }
    }
  });

  wait_for_step = function(step) {
    var deferred, promise;
    log('wait_for_step', step);
    if (__indexOf.call(received_steps, step) >= 0) {
      received_steps = _.without(received_steps, step);
      promise = _when.resolve();
    } else {
      deferred = _when.defer();
      step_listeners[step] = deferred.resolver;
      promise = deferred.promise;
    }
    promise.then(function() {
      return log('resolved step:', step);
    });
    return promise;
  };

  Steppers = (function() {

    function Steppers(windowNames) {
      var name, _i, _len;
      this.steppers = {};
      for (_i = 0, _len = windowNames.length; _i < _len; _i++) {
        name = windowNames[_i];
        this.steppers[name] = Stepper();
      }
    }

    Steppers.prototype.run = function(who) {
      return this.steppers[who].run().then((function(result) {
        log('result', result);
        return _when.resolve();
      }), (function(reason) {
        log('failed', reason);
        return _when.reject(reason);
      }));
    };

    return Steppers;

  })();

  setup_test = function(testName, who) {
    var child1, parent, steppers, _ref;
    log('test ' + testName, who);
    steppers = new Steppers(['parent', 'child1']);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      log('begin test ' + testName);
      Meteor.BrowserCollection.reset();
      return Meteor.BrowserCollection.erase_database();
    });
    parent(function() {
      log('sending run_test');
      Meteor.BrowserMsg.send('run_test', 'child1', testName);
      return Meteor.BrowserMsg.send('test_step', 'child1', 'run test');
    });
    child1(function() {
      log('begin test ' + testName);
      return wait_for_step('run test');
    });
    child1(function() {
      Meteor.BrowserCollection.reset();
      return Meteor.BrowserMsg.send('test_step', 'parent', 'child1 ready');
    });
    parent(function() {
      return wait_for_step('child1 ready');
    });
    return steppers;
  };

  test_persistent = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('persistent', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      var _this = this;
      return this.foo = new Meteor.BrowserCollection('foo', function() {
        return insert_four(_this.foo, function() {
          return Meteor.BrowserMsg.send('test_step', 'child1', 'collection created');
        });
      });
    });
    child1(function() {
      return wait_for_step('collection created');
    });
    child1(function() {
      var _this = this;
      return this.foo = new Meteor.BrowserCollection('foo', function() {
        var count;
        if ((count = _this.foo.find().count()) === 4) {
          return Meteor.BrowserMsg.send('test_step', 'parent', 'got it');
        } else {
          return log('FAILED: expected 4 documents, but found', count);
        }
      });
    });
    parent(function() {
      return wait_for_step('got it');
    });
    parent(function() {
      log('all done!');
      return true;
    });
    return steppers.run(who);
  };

  test_insert = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('insert', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      return this.foo = new Meteor.BrowserCollection('foo', function() {
        return Meteor.BrowserMsg.send('test_step', 'child1', 'collection created');
      });
    });
    child1(function() {
      return wait_for_step('collection created');
    });
    child1(function() {
      var done;
      done = _when.defer();
      log('starting test_insert');
      this.foo = new Meteor.BrowserCollection('foo', function() {
        Meteor.BrowserMsg.send('test_step', 'parent', 'child1 is ready to start test_insert');
        return done.resolve();
      });
      return done.promise;
    });
    parent(function() {
      return wait_for_step('child1 is ready to start test_insert');
    });
    parent(function() {
      log('inserting');
      return this.foo.insert({
        abc: 123
      }, function() {
        return log('inserted... will child1 see the inserted document?');
      });
    });
    child1(function() {
      this.foo.find().observe({
        added: function(doc) {
          log('I see document added:', doc);
          if (doc.abc === 123) {
            return Meteor.BrowserMsg.send('test_step', 'parent', 'child1 saw inserted document');
          }
        }
      });
      return true;
    });
    parent(function() {
      return wait_for_step('child1 saw inserted document');
    });
    parent(function() {
      log('all done!');
      return true;
    });
    return steppers.run(who);
  };

  test_update = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('update', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        _this.doc_id = _this.foo.insert({
          abc: 123
        }, function() {
          return Meteor.BrowserMsg.send('test_step', 'child1', 'start watching foo');
        });
        return log('inserted', _this.doc_id);
      });
      return null;
    });
    child1(function() {
      return wait_for_step('start watching foo');
    });
    child1(function() {
      var _this = this;
      return this.foo = new Meteor.BrowserCollection('foo', function() {
        if (_this.foo.findOne().abc === 123) {
          return Meteor.BrowserMsg.send('test_step', 'parent', 'have foo');
        }
      });
    });
    parent(function() {
      return wait_for_step('have foo');
    });
    parent(function() {
      log('updating');
      return this.foo.update(this.doc_id, {
        def: 456
      });
    });
    child1(function() {
      log('observing');
      return this.foo.find().observe({
        changed: function(doc) {
          log('changed doc', doc);
          if (doc.def === 456) {
            return Meteor.BrowserMsg.send('test_step', 'parent', 'got it');
          }
        }
      });
    });
    parent(function() {
      return wait_for_step('got it');
    });
    return steppers.run(who);
  };

  insert_four = function(collection, cb) {
    var doc_id1,
      _this = this;
    return doc_id1 = collection.insert({
      abc: 11,
      color: 'red'
    }, function() {
      var doc_id2;
      return doc_id2 = collection.insert({
        abc: 22,
        color: 'red'
      }, function() {
        var doc_id3;
        return doc_id3 = collection.insert({
          abc: 33,
          color: 'green'
        }, function() {
          var doc_id4;
          return doc_id4 = collection.insert({
            abc: 44,
            color: 'green'
          }, function() {
            return cb(null, {
              doc_id1: doc_id1,
              doc_id2: doc_id2,
              doc_id3: doc_id3,
              doc_id4: doc_id4
            });
          });
        });
      });
    });
  };

  test_update_multiple = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('update_multiple', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        return insert_four(_this.foo, function() {
          return Meteor.BrowserMsg.send('test_step', 'child1', 'start watching foo');
        });
      });
      return null;
    });
    child1(function() {
      return wait_for_step('start watching foo');
    });
    child1(function() {
      var _this = this;
      return this.foo = new Meteor.BrowserCollection('foo', function() {
        if (_this.foo.find().count() === 4) {
          return Meteor.BrowserMsg.send('test_step', 'parent', 'have foo');
        }
      });
    });
    parent(function() {
      return wait_for_step('have foo');
    });
    parent(function() {
      return this.foo.update({
        color: 'red'
      }, {
        $set: {
          abc: 99
        }
      }, {
        multi: true
      });
    });
    child1(function() {
      var next,
        _this = this;
      next = _when.defer();
      this.number_changed = 0;
      this.foo.find().observe({
        changed: function(doc) {
          if (_this.number_changed === 0) {
            setImmediate(function() {
              return next.resolve();
            });
          }
          return ++_this.number_changed;
        }
      });
      return next.promise;
    });
    child1(function() {
      if (this.number_changed === 2) {
        return Meteor.BrowserMsg.send('test_step', 'parent', 'got it');
      } else {
        return log('FAILED: expected number changed to be 2, but was', this.number_changed);
      }
    });
    parent(function() {
      return wait_for_step('got it');
    });
    return steppers.run(who);
  };

  test_remove = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('remove', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        return _this.doc_id = _this.foo.insert({
          abc: 123
        }, function() {
          return Meteor.BrowserMsg.send('test_step', 'child1', 'start watching foo');
        });
      });
      return null;
    });
    child1(function() {
      return wait_for_step('start watching foo');
    });
    child1(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        if (_this.foo.findOne().abc === 123) {
          return Meteor.BrowserMsg.send('test_step', 'parent', 'have foo');
        }
      });
      return null;
    });
    parent(function() {
      return wait_for_step('have foo');
    });
    parent(function() {
      return this.foo.remove(this.doc_id);
    });
    child1(function() {
      log('watching for removed doc');
      return this.foo.find().observe({
        removed: function(doc) {
          log('doc removed', doc);
          return Meteor.BrowserMsg.send('test_step', 'parent', 'got it');
        }
      });
    });
    parent(function() {
      return wait_for_step('got it');
    });
    return steppers.run(who);
  };

  test_remove_multiple = function(who) {
    var child1, parent, steppers, _ref;
    steppers = setup_test('remove_multiple', who);
    _ref = steppers.steppers, parent = _ref.parent, child1 = _ref.child1;
    parent(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        return insert_four(_this.foo, function() {
          return Meteor.BrowserMsg.send('test_step', 'child1', 'start watching foo');
        });
      });
      return null;
    });
    child1(function() {
      return wait_for_step('start watching foo');
    });
    child1(function() {
      var _this = this;
      this.foo = new Meteor.BrowserCollection('foo', function() {
        if (_this.foo.find().count() === 4) {
          return Meteor.BrowserMsg.send('test_step', 'parent', 'have foo');
        }
      });
      return null;
    });
    parent(function() {
      return wait_for_step('have foo');
    });
    parent(function() {
      return this.foo.remove({
        color: 'red'
      });
    });
    child1(function() {
      var next,
        _this = this;
      next = _when.defer();
      log('watching for removed docs');
      this.number_removed = 0;
      this.foo.find().observe({
        removed: function(doc) {
          log('doc removed', doc);
          if (_this.number_removed === 0) {
            setImmediate(function() {
              return next.resolve();
            });
          }
          return ++_this.number_removed;
        }
      });
      return next.promise;
    });
    child1(function() {
      if (this.number_removed === 2) {
        return Meteor.BrowserMsg.send('test_step', 'parent', 'got it');
      } else {
        return log('FAILED: expected number removed to be 2, but was', this.number_removed);
      }
    });
    parent(function() {
      return wait_for_step('got it');
    });
    return steppers.run(who);
  };

  Template.route.show_parent = function() {
    return Session.equals('show', 'parent');
  };

  Template.route.show_child1 = function() {
    return Session.equals('show', 'child1');
  };

  child1_started = false;

  Template.child1.created = function() {
    if (child1_started) {
      throw new Error('oops, child1 already started');
    }
    child1_started = true;
    log('ready');
    return Meteor.BrowserMsg.send('ready', 'child1');
  };

  switch (window.location.pathname) {
    case '/':
      window.name = 'parent';
      Meteor.BrowserMsg.listen({
        log: function() {
          var args;
          args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
          return log0.apply(null, args);
        }
      });
      Session.set('show', 'parent');
      break;
    case '/child1':
      Session.set('show', 'child1');
      log('listening for run_test');
      Meteor.BrowserMsg.listen({
        run_test: function(who, testName) {
          log('received run_test', who, testName);
          if (who === 'child1') {
            if (testName === 'persistent') {
              return test_persistent('child1');
            } else if (testName === 'insert') {
              return test_insert('child1');
            } else if (testName === 'update') {
              return test_update('child1');
            } else if (testName === 'update_multiple') {
              return test_update_multiple('child1');
            } else if (testName === 'remove') {
              return test_remove('child1');
            } else if (testName === 'remove_multiple') {
              return test_remove_multiple('child1');
            }
          }
        }
      });
  }

  child1_ready = _when.defer();

  Meteor.windowtest.beforeTests(function(onComplete) {
    return child1_ready.then(function() {
      return onComplete();
    });
  });

  Meteor.BrowserMsg.listen({
    'ready': function(name) {
      if (name === 'child1') {
        return child1_ready.resolve();
      }
    }
  });

  check = function(test, onComplete, promise) {
    return promise.then((function() {
      return onComplete();
    }), (function(reason) {
      test.fail({
        type: "windowtest",
        message: reason.toString()
      });
      return onComplete();
    }));
  };

  addTest = function(testName, impl) {
    return Tinytest.addAsync(testName, function(test, onComplete) {
      var promise;
      log('');
      log('------ test ' + testName);
      try {
        promise = impl('parent');
      } catch (e) {
        console.log(e.stack);
      }
      if (promise != null) {
        return check(test, onComplete, promise);
      }
    });
  };

  sql = Meteor.BrowserCollection._store.implementation === 'SQL';

  addTest('documents are persistent', test_persistent);

  addTest('insert', test_insert);

  addTest('update', test_update);

  addTest('update_multiple', test_update_multiple);

  addTest('remove', test_remove);

  addTest('remove_multiple', test_remove_multiple);

}).call(this);
