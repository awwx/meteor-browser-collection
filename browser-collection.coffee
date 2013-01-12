_when = @when

# assumes "onsuccess" is called only once, so don't use for cursors

request_to_promise = (req) ->
  pend = _when.defer()
  req.onerror   = (event) -> pend.reject()  #TODO reason: req.error
  req.onsuccess = (event) -> pend.resolve(req.result)
  pend.promise


class IndexedStore

  constructor: ->

  delete_database: (database_name) ->
    request_to_promise(window.indexedDB.deleteDatabase(database_name))

  open_database: (database_name, version, onUpgradeNeeded) ->
    req = window.indexedDB.open(database_name, version)
    req.onupgradeneeded = (event) ->
      onUpgradeNeeded(event.target.result)
    request_to_promise req

  transaction: (withTransaction) ->
    deferred = _when.defer()
    tx = @idb.transaction(['documents'], 'readwrite')
    tx.oncomplete = => deferred.resolve()
    tx.onerror = (event) => deferred.reject(event.target.errorCode)
    _when(
      withTransaction(tx),
      null,
      ((error) => deferred.reject(error))
    )
    deferred.promise

  get: (store, key) ->
    request_to_promise store.get(key)

  add: (store, val) ->
    request_to_promise store.add(val)

  put: (store, val) ->
    require_to_promise store.put(val)

  del: (store, key) ->
    require_to_promise store.delete(key)

  setup_database: (db) ->
    console.log '*** setting up database'
    store = db.createObjectStore('documents', {keyPath: '_id'})
    store.createIndex('collection', 'collection', {unique: false})
    undefined

  open: ->
    console.log '*** opening database'
    @open_database('Meteor.BrowserCollection', 1, (db) => @setup_database(db))
    .then((db) =>
      @idb = db
      undefined
    )

  dump: ->
    @transaction (tx) =>
      documents = tx.objectStore('documents')
      console.log 'documents', documents
      req = documents.openCursor()
      req.onerror = (event) -> console.log 'dump error', event
      req.onsuccess = (event) ->
        cursor = req.result
        if cursor?
          console.log cursor.value
          cursor.continue()
      undefined

  fetch_all_docs: (collectionName, tx) ->
    documents = tx.objectStore('documents')
    request_to_promise(documents.index('collection').openCursor(collectionName))
    .then((cursor) =>
      console.log 'have cursor', cursor
      undefined
    )
    _when.resolve([])

  insert_doc: (collectionName, tx, doc) ->
    documents = tx.objectStore('documents')
    @add(documents, doc)


class SQLStore

  constructor: ->

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
        console.log 'create database error', error
        result.reject(error)
      ),
      (=>
        result.resolve()
      )
    result.promise

  transaction: (withTransaction) ->
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

  insert_doc: (collectionName, tx, doc) ->
    tx.executeSql 'INSERT INTO documents (id, collection, document) VALUES (?, ?, ?)',
      [doc._id, collectionName, JSON.stringify(doc)]
    undefined


if window.indexedDB?
  store = new IndexedStore()
else if window.openDatabase?
  store = new SQLStore()
else
  console.log 'BrowserCollection storage not supported'
  store = null

window.store = store

if store?
  store.open()
  .otherwise((error) ->
    console.log 'BrowserCollection database open error', error
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
    store.transaction(
      ((tx) =>
        store.fetch_all_docs(@_name, tx)
        .then((docs) =>
          for doc in docs
            @_localCollection.insert(doc)
          undefined
        )
      )
    )
    .then(
      (=>
        cb?()
        undefined
      ),
      ((error) =>
        console.log 'BrowserCollection load transaction error', error
        console.log error.stack if error.stack?
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
    store.sqldb.transaction(
      ((tx) =>
        tx.executeSql(
          'SELECT document FROM documents WHERE collection=? AND id=?',
          [@_name, doc_id],
          ((tx, result) =>
            if result.rows.length is 1
              doc = JSON.parse(result.rows.item(0).document)
          )
        )
      ),
      ((error) => console.log error),
      (=>
        @_cache_set doc_id, doc
      )
    )

  _fetch_all_docs: (tx, cb) ->
    tx.executeSql(
      'SELECT document FROM documents WHERE collection=?',
      [@_name],
      ((tx, result) =>
        docs = []
        for i in [0 ... result.rows.length]
          docs.push JSON.parse(result.rows.item(i).document)
        cb(docs)
      )
    )

  _update_doc: (tx, doc) ->
    tx.executeSql(
      'UPDATE documents SET document=? WHERE id=?',
      [JSON.stringify(doc), doc._id]
    )

  _delete_doc: (tx, doc_id) ->
    tx.executeSql(
      'DELETE FROM documents WHERE id=?',
      [doc_id]
    )

  _reload_all: ->
    docs = null
    store.sqldb.transaction(
      ((tx) =>
        @_fetch_all_docs tx, (_docs) =>
          docs = _docs
      ),
      ((error) => console.log error),
      (=>
        oldResults = idMap(@_localCollection.find().fetch())
        newResults = idMap(docs)
        LocalCollection._diffQueryUnordered oldResults, newResults,
          added:   (newDoc) => @_localCollection.insert newDoc
          changed: (newDoc) => @_localCollection.update newDoc._id, newDoc
          removed: (oldDoc) => @_localCollection.remove oldDoc._id
      )
    )

  insert: (doc, callback) ->
    if doc._id?
      throw new Error 'inserted doc should not yet have an _id attribute'
    doc._id = LocalCollection.uuid()
    store.transaction(
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
        console.log 'insert transaction error', error
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
    store.sqldb.transaction(
      ((tx) =>
        tx.executeSql(
          'SELECT document FROM documents WHERE id=?',
          [doc_id],
          ((tx, result) =>
            return if result.rows.length isnt 1
            doc = JSON.parse(result.rows.item(0).document)
            LocalCollection._modify(doc, modifier)
            @_update_doc tx, doc
          )
        )
      ),
      ((error) =>
        console.log 'modify transaction error', error
        callback?(error)
        undefined
      ),
      (=>
        @_cache_set doc_id, doc
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.single', @_name, doc_id
        callback?()
        undefined
      )
    )

  _update_multiple: (selector, modifier, options, callback) ->
    compiledSelector = LocalCollection._compileSelector(selector)
    modified_docs = []
    store.sqldb.transaction(
      ((tx) =>
        @_fetch_all_docs tx, (docs) =>
          for doc in docs
            if compiledSelector(doc)
              LocalCollection._modify(doc, modifier)
              @_update_doc tx, doc
              modified_docs.push doc
              break unless options?.multi
          undefined
      ),
      ((error) =>
        console.log 'update transaction error', error
        callback?()
        undefined
      ),
      (=>
        for doc in modified_docs
          @_localCollection.update doc._id, doc
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.reloadAll', @_name
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
    store.sqldb.transaction(
      ((tx) =>
        @_delete_doc tx, doc_id
      ),
      ((error) =>
        console.log 'remove transaction error', error
        callback?()
        undefined
      ),
      ((tx, result) =>
        @_localCollection.remove(doc_id)
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.single', @_name, doc_id
        callback?()
        undefined
      )
    )

  _remove_multiple: (selector, callback) ->
    compiledSelector = LocalCollection._compileSelector(selector)
    deleted = []
    store.sqldb.transaction(
      ((tx) =>
        @_fetch_all_docs tx, (docs) =>
          for doc in docs
            if compiledSelector(doc)
              @_delete_doc tx, doc._id
              deleted.push doc._id
          undefined
      ),
      ((error) =>
        console.log 'remove transaction error', error
        callback?(error)
        undefined
      ),
      (=>
        for doc_id in deleted
          @_localCollection.remove(doc_id)
        Meteor.BrowserMsg.send 'Meteor.BrowserCollection.reloadAll', @_name
        callback?()
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

Meteor.BrowserCollection.erase = ->
  done = _when.defer()
  # TODO not good if other windows already have a collection open
  unless _.isEmpty(collections)
    throw new Error("call erase() before opening any collections")
  store.sqldb.transaction(
    ((tx) -> tx.executeSql('DELETE FROM documents')),
    ((error) ->
      console.log 'erase transaction error', error
      done.reject(error)
    ),
    (->
      console.log 'erase transaction success'
      done.resolve()
    )
  )
  done.promise

Meteor.BrowserCollection.reset = ->
  #TODO dispose existing collections?
  collections = {}
