_when = @when

# Sigh, Firefox console log displays not what an object *was* at the time it
# was logged to the console but what it contains *now*.
#
# What ever happened to teletypes...

debugStringify = (x) ->
  if x instanceof DOMException
    x.toString()
  else if x?.stack?
    JSON.stringify(x.message) + ":\n" + x.stack.toString()
  else if _.isString(x)
    x
  else if _.isUndefined(x)
    'undefined'
  else if _.isNull(x)
    'null'
  else
    try
      return JSON.stringify(x)
    catch e
      return x.toString()

debugLog = errorLog = (args...) ->
  args = _.map(args, debugStringify)
  console.log args...

catcherr = (fn) ->
  _when.resolve().then(fn)


# assumes "onsuccess" is called only once, so don't use for cursors

request_to_promise = (req) ->
  deferred = _when.defer()
  req.onerror   = (event) -> deferred.reject()  #TODO reason: req.error
  req.onsuccess = (event) -> deferred.resolve(req.result)
  deferred.promise

promize = (fn) ->
  deferred = _when.defer()
  req = null
  try
    req = fn()
  catch e
    errorLog 'promize error', e
    deferred.reject(e)
  if req?
    req.onerror   = (event) -> deferred.reject()  #TODO reason: req.error
    req.onsuccess = (event) -> deferred.resolve(req.result)
  deferred.promise


class IndexedStore

  constructor: ->

  implementation: 'IndexedDB'

  delete_database: (database_name) ->
    request_to_promise(window.indexedDB.deleteDatabase(database_name))

  open_database: (database_name, version, onUpgradeNeeded) ->
    req = window.indexedDB.open(database_name, version)
    req.onupgradeneeded = (event) ->
      onUpgradeNeeded(event.target.result)
    request_to_promise req

  transaction: (desc, withTransaction) ->
    deferred = _when.defer()
    debugLog ">> #{desc} begin transaction"
    tx = @idb.transaction(['documents'], 'readwrite')
    tx.oncomplete = =>
      debugLog "<< #{desc} transaction complete"
      deferred.resolve()
    tx.onerror = (event) =>
      errorLog '<< #{desc} transaction error', event
      deferred.reject(event.target.errorCode)
    valueOrPromise = catcherr -> withTransaction(tx)
    _when(
      valueOrPromise,
      null,
      ((error) =>
        debugLog "-- #{desc} error in transaction:", error
        deferred.reject(error)
      )
    )
    deferred.promise.then(
      (=>
        debugLog "-- #{desc} transaction promise resolved"
      ),
      ((error) =>
        debugLog "-- #{desc} transaction promise rejected:", error
      )
    )
    deferred.promise

  get: (store, key) ->
    request_to_promise store.get(key)

  add: (store, val) ->
    request_to_promise store.add(val)

  put: (store, val) ->
    promize -> store.put(val)

  del: (store, key) ->
    promize -> store.delete(key)

  setup_database: (db) ->
    debugLog '*** setting up IndexDB database'
    store = db.createObjectStore('documents', {keyPath: 'id'})
    store.createIndex('collection', 'collection', {unique: false})
    undefined

  open: ->
    debugLog '*** opening IndexDB database'
    @open_database('Meteor.BrowserCollection', 1, (db) => @setup_database(db))
    .then((db) =>
      @idb = db
      undefined
    )

  dump: ->
    @transaction('dump', (tx) =>
      documents = tx.objectStore('documents')
      req = documents.openCursor()
      req.onerror = (event) ->
        errorLog 'dump error', event
      req.onsuccess = (event) ->
        cursor = req.result
        if cursor?
          errorLog cursor.value
          cursor.continue()
      undefined
    )

  fetch_all_docs: (collectionName, tx) ->
    deferred = _when.defer()
    docs = []
    documents = tx.objectStore('documents')
    req = documents.index('collection').openCursor(collectionName)
    req.onerror = (event) ->
      errorLog 'fetch_all_docs error', event
      deferred.reject()
    req.onsuccess = (event) ->
      cursor = req.result
      if cursor?
        docs.push cursor.value.doc
        cursor.continue()
      else
        deferred.resolve(docs)
      undefined
    deferred.promise

  fetch_doc_by_id: (tx, collectionName, doc_id) ->
    documents = tx.objectStore('documents')
    @get(documents, doc_id)
    .then((document) => document.doc)

  insert_doc: (collectionName, tx, doc) ->
    documents = tx.objectStore('documents')
    @add(documents, {id: doc._id, collection: collectionName, doc: doc})

  update_doc: (tx, collectionName, doc) ->
    catcherr =>
      documents = tx.objectStore('documents')
      @put(documents, {id: doc._id, collection: collectionName, doc: doc})

  delete_doc: (tx, doc_id) ->
    catcherr =>
      documents = tx.objectStore('documents')
      @del(documents, doc_id)

  erase_database: ->
    @transaction 'erase_database', (tx) =>
      documents = tx.objectStore('documents')
      req = documents.openCursor()
      req.onerror = (event) ->
        errorLog 'erase_database error', event
        # TODO abort transaction?
      req.onsuccess = (event) ->
        cursor = req.result
        if cursor?
          documents.delete(cursor.key)
          cursor.continue()
      undefined


class SQLStore

  constructor: ->

  implementation: 'SQL'

  open: ->
    try
      @sqldb = openDatabase 'Meteor.BrowserCollection', '', '', 1024 * 1024
    catch e
      return _when.reject(e)

    if @sqldb.version is ''
      @setupDatabase()
    else
      _when.resolve()

  setupDatabase: ->
    result = _when.defer()
    @sqldb.changeVersion '', '1',
      ((tx) =>
        tx.executeSql(
          'CREATE TABLE documents (
             id TEXT NOT NULL PRIMARY KEY,
             collection TEXT NOT NULL,
             document TEXT NOT NULL
           )
          '
        )
        tx.executeSql(
          'CREATE INDEX collections ON documents (collection)'
        )
      ),
      ((error) =>
        errorLog 'create database error', error
        result.reject(error)
      ),
      (=>
        result.resolve()
      )
    result.promise

  transaction: (desc, withTransaction) ->
    throw new Error('withTransaction should be a function') unless _.isFunction(withTransaction)
    deferred = _when.defer()
    @sqldb.transaction(
      ((tx) =>
        _when(
          withTransaction(tx),
          null,
          ((error) -> deferred.reject(error))
        )
        undefined
      ),
      ((error) =>
        deferred.reject(error)
        undefined
      ),
      (=>
        deferred.resolve()
        undefined
      )
    )
    deferred.promise

  fetch_all_docs: (collectionName, tx) ->
    deferred = _when.defer()
    tx.executeSql(
      'SELECT document FROM documents WHERE collection=?',
      [collectionName],
      ((tx, result) =>
        docs = []
        for i in [0 ... result.rows.length]
          docs.push JSON.parse(result.rows.item(i).document)
        deferred.resolve(docs)
      )
    )
    deferred.promise

  fetch_doc_by_id: (tx, collectionName, doc_id) ->
    deferred = _when.defer()
    tx.executeSql(
      'SELECT document FROM documents WHERE collection=? AND id=?',
      [collectionName, doc_id],
      ((tx, result) =>
        if result.rows.length is 1
          deferred.resolve(JSON.parse(result.rows.item(0).document))
        else
          deferred.resolve(null)
        undefined
      )
    )
    deferred.promise

  insert_doc: (collectionName, tx, doc) ->
    tx.executeSql(
      'INSERT INTO documents (id, collection, document) VALUES (?, ?, ?)',
      [doc._id, collectionName, JSON.stringify(doc)]
    )
    undefined

  update_doc: (tx, collectionName, doc) ->
    tx.executeSql(
      'UPDATE documents SET document=? WHERE id=?',
      [JSON.stringify(doc), doc._id]
    )
    undefined

  delete_doc: (tx, doc_id) ->
    tx.executeSql(
      'DELETE FROM documents WHERE id=?',
      [doc_id]
    )
    undefined

  erase_database: ->
    deferred = _when.defer()
    @sqldb.transaction(
      ((tx) -> tx.executeSql('DELETE FROM documents')),
      ((error) ->
        errorLog 'erase transaction error', error
        deferred.reject(error)
      ),
      (->
        deferred.resolve()
      )
    )
    deferred.promise

  dump: ->
    _when.resolve()


if window.indexedDB?
  store = new IndexedStore()
else if window.openDatabase?
  store = new SQLStore()
else
  errorLog 'BrowserCollection storage not supported'
  store = null

window.store = store

if store?
  store.open()
  .otherwise((error) ->
    errorLog 'BrowserCollection database open error', error
    store = null
  )

collections = {}

Meteor.BrowserMsg.listen
  'Meteor.BrowserCollection.single': (collection_name, doc_id) ->
    collections[collection_name]?._reload_single(doc_id)

  'Meteor.BrowserCollection.reloadAll': (collection_name) ->
    collections[collection_name]?._reload_all()

Meteor.BrowserCollection = (name, cb) ->
  unless store?
    throw new Error('BrowserCollection storage is not supported in this browser')

  if collections[name]?
    throw new Error('a BrowserCollection with this name has already been created: ' + name)

  @_name = name
  @_localCollection = new LocalCollection()
  collections[name] = @
  @_load(cb)
  undefined

Meteor.BrowserCollection._store = store

each_sql_result = (result, callback) ->
  for i in [0 ... result.rows.length]
    callback(result.rows.item(i))

result_as_array = (result) ->
  a = []
  for i in [0 ... result.rows.length]
    a.push result.rows.item(i)
  a

idOf = (doc) -> doc._id

idMap = (arrayOfDocs) ->
  result = {}
  for doc in arrayOfDocs
    result[idOf(doc)] = doc
  result

_.extend Meteor.BrowserCollection.prototype,

  _load: (cb) ->
    docs = null
    store.transaction(
      '_load',
      ((tx) =>
        store.fetch_all_docs(@_name, tx)
        .then((_docs) => docs = _docs)
      )
    )
    .then(
      (=>
        for doc in docs
          @_localCollection.insert(doc)
        cb?()
        undefined
      ),
      ((error) =>
        errorLog 'BrowserCollection load transaction error', error
        errorLog error.stack if error.stack?
        cb?(error)
        undefined
      ),
    )

  _cache_set: (doc_id, doc) ->
    if doc?
      if @_localCollection.findOne(doc._id)?
        @_localCollection.update doc._id, doc
      else
        @_localCollection.insert doc
    else
      @_localCollection.remove doc_id
    undefined

  _reload_single: (doc_id) ->
    doc = null
    store.transaction(
      '_reload_single',
      ((tx) =>
        store.fetch_doc_by_id(tx, @_name, doc_id)
        .then((_doc) =>
          doc = _doc
          undefined
        )
        undefined
      )
    )
    .then(
      (=>
        @_cache_set doc_id, doc
        undefined
      ),
      ((error) =>
        errorLog '_reload_single transaction error', error
        _when.reject(error)
      )
    )

  _reload_all: ->
    docs = null
    store.transaction('_reload_all', (tx) =>
      store.fetch_all_docs(@_name, tx)
      .then((_docs) => docs = _docs)
    )
    .then(
      (=>
        oldResults = idMap(@_localCollection.find().fetch())
        newResults = idMap(docs)
        LocalCollection._diffQueryUnordered oldResults, newResults,
          added:   (newDoc) => @_localCollection.insert newDoc
          changed: (newDoc) => @_localCollection.update newDoc._id, newDoc
          removed: (oldDoc) => @_localCollection.remove oldDoc._id
        undefined
      ),
      ((error) => errorLog '_reload_all transaction error', error)
    )

  insert: (doc, callback) ->
    if doc._id?
      throw new Error 'inserted doc should not yet have an _id attribute'
    doc._id = LocalCollection.uuid()
    store.transaction(
      'insert',
      ((tx) =>
        store.insert_doc(@_name, tx, doc)
      )
    )
    .then(
      (=>
        @_localCollection.insert(doc)
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.single', @_name, doc._id
        callback?(null, doc._id)
        undefined
      ),
      ((error) =>
        # TODO might be out of space?
        errorLog 'insert transaction error', error
        callback?(error)
        undefined
      )
    )
    doc._id

  find: (arg...) ->
    @_localCollection.find(arg...)

  findOne: (arg...) ->
    @_localCollection.findOne(arg...)

  _update_single: (doc_id, modifier, options, callback) ->
    doc = null
    store.transaction(
      '_update_single'
      ((tx) =>
        store.fetch_doc_by_id(tx, @_name, doc_id)
        .then((_doc) =>
          doc = _doc
          LocalCollection._modify(doc, modifier)
          store.update_doc tx, @_name, doc
        )
      )
    )
    .then(
      (=>
        @_cache_set doc_id, doc
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.single', @_name, doc_id
        callback?()
        undefined
      ),
      ((error) =>
        errorLog 'update transaction error', error
        callback?(error)
        undefined
      ),
    )

  _update_multiple: (selector, modifier, options, callback) ->
    compiledSelector = LocalCollection._compileSelector(selector)
    modified_docs = []
    store.transaction(
      '_update_multiple',
      ((tx) =>
        store.fetch_all_docs(@_name, tx)
        .then((docs) =>
          for doc in docs
            if compiledSelector(doc)
              LocalCollection._modify(doc, modifier)
              store.update_doc tx, @_name, doc
              modified_docs.push doc
              break unless options?.multi
          undefined
        )
      )
    )
    .then(
      (=>
        for doc in modified_docs
          @_localCollection.update doc._id, doc
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.reloadAll', @_name
        callback?()
        undefined
      ),
      ((error) =>
        errorLog 'update transaction error', error
        callback?()
        undefined
      )
    )

  update: (selector, modifier, options, callback) ->
    if _.isFunction(options)
      callback = options
      options = {}
    if LocalCollection._selectorIsId(selector)
      @_update_single selector, modifier, options, callback
    else
      @_update_multiple selector, modifier, options, callback
    undefined

  _remove_single: (doc_id, callback) ->
    store.transaction('_remove_single', (tx) =>
      store.delete_doc tx, doc_id
    )
    .then(
      (=>
        @_localCollection.remove(doc_id)
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.single', @_name, doc_id
        callback?()
        undefined
      ),
      ((error) =>
        errorLog 'remove transaction error', error
        callback?(error)
        undefined
      ),
    )
    undefined

  _remove_multiple: (selector, callback) ->
    compiledSelector = LocalCollection._compileSelector(selector)
    deleted = []
    store.transaction('_remove_multiple', (tx) =>
      store.fetch_all_docs(@_name, tx)
      .then((docs) =>
        for doc in docs
          if compiledSelector(doc)
            store.delete_doc tx, doc._id
            deleted.push doc._id
        undefined
      )
    )
    .then(
      (=>
        for doc_id in deleted
          @_localCollection.remove(doc_id)
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.reloadAll', @_name
        callback?()
        undefined
      ),
      ((error) =>
        errorLog 'remove transaction error', error
        callback?(error)
        undefined
      )
    )

  remove: (selector, callback) ->
    return unless selector?
    if LocalCollection._selectorIsId(selector)
      @_remove_single(selector, callback)
    else
      @_remove_multiple(selector, callback)
    undefined

Meteor.BrowserCollection.erase_database = ->
  # TODO not good if other windows already have a collection open
  unless _.isEmpty(collections)
    throw new Error("call erase_database() before opening any collections")
  store.erase_database()

Meteor.BrowserCollection.reset = ->
  #TODO dispose existing collections?
  collections = {}
