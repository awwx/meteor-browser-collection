if Meteor.isServer
  Meteor.methods
    log: (args...) ->
      console.log args...
      null

return unless Meteor.isClient

Meteor.windowtest.numberOfWindowsToOpen 1

_when = window.when

log0 = (args...) ->
  console?.log? args...
  msg = _.map(args, (arg) -> if _.isString(arg) then arg else JSON.stringify(arg)).join(' ') + "\n"
  $('#log').append(document.createTextNode(msg))
  e = $('#log')[0]
  e.scrollTop = e.scrollHeight if e?
  Meteor.call 'log', args..., (error) -> console?.log? error if error?
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
    Meteor.BrowserCollection.reset()
    Meteor.BrowserCollection.erase()

  parent ->
    log 'sending run_test'
    Meteor.BrowserMsg.send 'run_test', 'child1', testName
    Meteor.BrowserMsg.send 'test_step', 'child1', 'run test'

  child1 ->
    log 'begin test ' + testName
    wait_for_step 'run test'

  child1 ->
    Meteor.BrowserCollection.reset()
    Meteor.BrowserMsg.send 'test_step', 'parent', 'child1 ready'

  parent ->
    wait_for_step 'child1 ready'

  steppers


test_persistent = (who) ->
  steppers = setup_test 'persistent', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      insert_four @foo, =>
        Meteor.BrowserMsg.send 'test_step', 'child1', 'collection created'

  child1 ->
    wait_for_step 'collection created'

  child1 ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      if (count = @foo.find().count()) is 4
        Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'
      else
        log 'FAILED: expected 4 documents, but found', count

  parent ->
    wait_for_step 'got it'

  parent ->
    log 'all done!'
    true

  steppers.run(who)


test_insert = (who) ->

  steppers = setup_test 'insert', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserCollection 'foo', ->
      Meteor.BrowserMsg.send 'test_step', 'child1', 'collection created'

  child1 ->
    wait_for_step 'collection created'

  child1 ->
    done = _when.defer()
    log 'starting test_insert'
    @foo = new Meteor.BrowserCollection 'foo', ->
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
    @foo = new Meteor.BrowserCollection 'foo', =>
      @doc_id = @foo.insert {abc: 123}, ->
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
      log 'inserted', @doc_id
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      if @foo.findOne().abc is 123
        Meteor.BrowserMsg.send 'test_step', 'parent', 'have foo'

  parent ->
    wait_for_step 'have foo'

  parent ->
    log 'updating'
    @foo.update @doc_id, {def: 456}

  child1 ->
    log 'observing'
    @foo.find().observe
      changed: (doc) ->
        log 'changed doc', doc
        if doc.def is 456
          Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'

  parent ->
    wait_for_step 'got it'

  steppers.run who

insert_four = (collection, cb) ->
  doc_id1 = collection.insert {abc: 11, color: 'red'}, =>
    doc_id2 = collection.insert {abc: 22, color: 'red'}, =>
      doc_id3 = collection.insert {abc: 33, color: 'green'}, =>
        doc_id4 = collection.insert {abc: 44, color: 'green'}, =>
          cb(null, {doc_id1, doc_id2, doc_id3, doc_id4})

test_update_multiple = (who) ->

  steppers = setup_test 'update_multiple', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      insert_four @foo, =>
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      if @foo.find().count() is 4
        Meteor.BrowserMsg.send 'test_step', 'parent', 'have foo'

  parent ->
    wait_for_step 'have foo'

  parent ->
    @foo.update {color: 'red'}, {$set: {abc: 99}}, {multi: true}

  child1 ->
    next = _when.defer()
    @number_changed = 0
    @foo.find().observe
      changed: (doc) =>
        if @number_changed == 0
          # We expect all observe events to be delivered within *this* tick of the
          # event loop, so continue in the *next* tick
          setImmediate => next.resolve()
        ++@number_changed
    next.promise

  child1 ->
   if @number_changed is 2
     Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'
   else
     log 'FAILED: expected number changed to be 2, but was', @number_changed

  parent ->
    wait_for_step 'got it'

  steppers.run who

test_remove = (who) ->
  steppers = setup_test 'remove', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      @doc_id = @foo.insert {abc: 123}, ->
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserCollection 'foo', =>
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

test_remove_multiple = (who) ->
  steppers = setup_test 'remove_multiple', who
  {parent, child1} = steppers.steppers

  parent ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      insert_four @foo, =>
        Meteor.BrowserMsg.send 'test_step', 'child1', 'start watching foo'
    null

  child1 ->
    wait_for_step 'start watching foo'

  child1 ->
    @foo = new Meteor.BrowserCollection 'foo', =>
      if @foo.find().count() is 4
        Meteor.BrowserMsg.send 'test_step', 'parent', 'have foo'
    null

  parent ->
    wait_for_step 'have foo'

  parent ->
    @foo.remove {color: 'red'}

  child1 ->
    next = _when.defer()
    log 'watching for removed docs'
    @number_removed = 0
    @foo.find().observe
      removed: (doc) =>
        log 'doc removed', doc
        if @number_removed is 0
          setImmediate => next.resolve()
        ++@number_removed
    next.promise

  child1 ->
    if @number_removed is 2
      Meteor.BrowserMsg.send 'test_step', 'parent', 'got it'
    else
      log 'FAILED: expected number removed to be 2, but was', @number_removed

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
        if testName is 'persistent'
          test_persistent('child1')
        else if testName is 'insert'
          test_insert('child1')
        else if testName is 'update'
          test_update('child1')
        else if testName is 'update_multiple'
          test_update_multiple('child1')
        else if testName is 'remove'
          test_remove('child1')
        else if testName is 'remove_multiple'
          test_remove_multiple('child1')

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

firefox = /Firefox/.test(navigator.userAgent)

addTest 'documents are persistent', test_persistent unless firefox
addTest 'insert', test_insert                       unless firefox
addTest 'update', test_update                       unless firefox
addTest 'update_multiple', test_update_multiple     unless firefox
addTest 'remove', test_remove                       unless firefox
addTest 'remove_multiple', test_remove_multiple     unless firefox
