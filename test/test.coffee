return unless Meteor.isClient

Meteor.windowtest.numberOfWindowsToOpen 1

_when = window.when

log0 = (args...) ->
  console?.log? args...
  msg = _.map(args, (arg) -> if _.isString(arg) then arg else JSON.stringify(arg)).join(' ') + "\n"
  $('#log').append(document.createTextNode(msg))
  e = $('#log')[0]
  # oops, was doing some logging before the template containing the "log" div is rendered
  return unless e?
  e.scrollTop = e.scrollHeight
  null

log = (args...) ->
  if window.name is 'child1'
    Meteor.BrowserMsg.send 'log', 'child1:', args...
  else
    log0 'parent:', args...

# child1_window = null

step_listeners = {}
received_steps = []

reset_steps = ->
  step_listeners = {}
  received_steps = []

Meteor.BrowserMsg.listen
  'test_step': (to, step) ->
    if to is window.name
      if step_listeners[step]?
        step_listeners[step].resolve()
      else
        received_steps.push(step)

wait_for_step = (step) ->
  log 'wait_for_step', step
  if step in received_steps
    received_steps = _.without(received_steps, step)
    promise = _when.resolve()
  else
    deferred = _when.defer()
    step_listeners[step] = deferred.resolver
    promise = deferred.promise
  promise.then -> log 'resolved step:', step
  promise

class Steppers

  constructor: (windowNames) ->
    @steppers = {}
    @steppers[name] = Stepper() for name in windowNames

  run: (who) ->
    @steppers[who].run()
    .then(
      ((result) ->
        log 'result', result
        _when.resolve()
      ),
      ((reason) ->
        log 'failed', reason
        _when.reject(reason)
      )
    )

setup_test = (testName, who) ->

  log 'test ' + testName, who

  steppers = new Steppers(['parent', 'child1'])
  {parent, child1} = steppers.steppers

  parent ->
    log 'begin test ' + testName
    Meteor.BrowserSQLCollection.reset()
    Meteor.BrowserSQLCollection.erase()

  parent ->
    log 'sending run_test'
    Meteor.BrowserMsg.send 'run_test', 'child1', testName
    Meteor.BrowserMsg.send 'test_step', 'child1', 'run test'

  child1 ->
    log 'begin test ' + testName
    wait_for_step 'run test'

  child1 ->
    Meteor.BrowserSQLCollection.reset()
    Meteor.BrowserMsg.send 'test_step', 'parent', 'child1 ready'

  parent ->
    wait_for_step 'child1 ready'

  steppers

test_insert = (who) ->

  steppers = setup_test 'insert', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserSQLCollection 'foo', ->
      Meteor.BrowserMsg.send 'test_step', 'child1', 'collection created'

  child1 ->
    wait_for_step 'collection created'

  child1 ->
    done = _when.defer()
    log 'starting test_insert'
    @foo = new Meteor.BrowserSQLCollection 'foo', ->
      Meteor.BrowserMsg.send 'test_step', 'parent', 'child1 is ready to start test_insert'
      done.resolve()
    done.promise

  parent ->
    wait_for_step 'child1 is ready to start test_insert'

  parent ->
    log 'inserting'
    @foo.insert {abc: 123}, ->
      log 'inserted... will child1 see the inserted document?'

  child1 ->
    @foo.find().observe
      added: (doc) ->
        log 'I see document added:', doc
        if doc.abc is 123
          Meteor.BrowserMsg.send 'test_step', 'parent', 'child1 saw inserted document'
    true

  parent ->
    wait_for_step 'child1 saw inserted document'

  parent ->
    log 'all done!'
    true

  steppers.run(who)

test_update = (who) ->

  steppers = setup_test 'update', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserSQLCollection 'foo', =>
      @doc_id = @foo.insert {abc: 123}, ->
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
      log 'inserted', @doc_id
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserSQLCollection 'foo', =>
      if @foo.findOne().abc is 123
        Meteor.BrowserMsg.send 'test_step', 'parent', 'have foo'

  parent ->
    wait_for_step 'have foo'

  parent ->
    @foo.update @doc_id, {def: 456}

  child1 ->
    @foo.find().observe
      changed: (doc) ->
        log 'changed doc', doc
        if doc.def is 456
          Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'

  parent ->
    wait_for_step 'got it'

  steppers.run who

test_remove = (who) ->
  steppers = setup_test 'remove', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserSQLCollection 'foo', =>
      @doc_id = @foo.insert {abc: 123}, ->
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserSQLCollection 'foo', =>
      if @foo.findOne().abc is 123
        Meteor.BrowserMsg.send 'test_step', 'parent', 'have foo'
    null

  parent ->
    wait_for_step 'have foo'

  parent ->
    @foo.remove @doc_id

  child1 ->
    log 'watching for removed doc'
    @foo.find().observe
      removed: (doc) ->
        log 'doc removed', doc
        Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'

  parent ->
    wait_for_step 'got it'

  steppers.run who

Template.route.show_parent = -> Session.equals('show', 'parent')
Template.route.show_child1 = -> Session.equals('show', 'child1')

child1_started = false
Template.child1.created = ->
  if child1_started then throw new Error('oops, child1 already started')
  child1_started = true
  log 'ready'
  Meteor.BrowserMsg.send 'ready', 'child1'

switch window.location.pathname
  when '/'
    window.name = 'parent'
    Meteor.BrowserMsg.listen
      log: (args...) -> log0 args...
    Session.set('show', 'parent')
  when '/child1'
    # window.name = 'child1'
    Session.set('show', 'child1')
    log 'listening for run_test'
    Meteor.BrowserMsg.listen run_test: (who, testName) ->
      log 'received run_test', who, testName
      if who is 'child1'
        if testName is 'insert'
          test_insert('child1')
        else if testName is 'update'
          test_update('child1')
        else if testName is 'remove'
          test_remove('child1')

child1_ready = _when.defer()

Meteor.windowtest.beforeTests (onComplete) ->
  child1_ready.then(-> onComplete())

Meteor.BrowserMsg.listen
  'ready': (name) ->
    child1_ready.resolve() if name is 'child1'

check = (test, onComplete, promise) ->
  promise.then(
    (-> onComplete()),
    ((reason) ->
      # TODO not seeing message in the test output
      test.fail({type: "windowtest", message: reason.toString()})
      onComplete()
    )
  )

addTest = (testName, impl) ->
  Tinytest.addAsync testName, (test, onComplete) ->
    log ''
    log '------ test ' + testName
    try
      promise = impl('parent')
    catch e
      console.log e.stack
    check test, onComplete, promise if promise?

addTest 'insert', test_insert
addTest 'update', test_update
addTest 'remove', test_remove
