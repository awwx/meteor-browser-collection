db = openDatabase 'Meteor.ClientCollection', '', '', 1024 * 1024, (db)

console.log 'version', JSON.stringify(db.version)

if db.version is ''
  db.changeVersion '', '1',
    ((tx) ->
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
    ((error) -> console.log 'create database error', error)
    (-> console.log 'create database success')

collections = {}

Meteor.LocalMsg.listen
  'Meteor.ClientCollection.single': (collection_name, doc_id) ->
    collections[collection_name]?._reload_single(doc_id)

Meteor.ClientSQLCollection = (name, cb) ->
  if collections[name]
    throw new Error('a ClientCollection with this name has already been created: ' + name)
  @_name = name
  @_localCollection = new LocalCollection()
  @_load(cb)
  collections[name] = @
  undefined

each_sql_result = (result, callback) ->
  for i in [0 ... result.rows.length]
    callback(result.rows.item(i))

result_as_array = (result) ->
  a = []
  for i in [0 ... result.rows.length]
    a.push result.rows.item(i)
  a

_.extend Meteor.ClientSQLCollection.prototype,

  _load: (cb) ->
    db.transaction(
      ((tx) =>
        tx.executeSql(
          'SELECT document FROM documents WHERE collection=?',
          [@_name],
          ((tx, result) =>
            each_sql_result result, (row) =>
              @_localCollection.insert(JSON.parse(row.document))
          )
        )
      ),
      ((error) => console.log error),
      (=> cb?())
    )

  _reload_single: (doc_id) ->
    doc = null
    db.transaction(
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
        if doc?
          @_localCollection.update doc._id, doc
      )
    )

  insert: (doc, callback) ->
    if doc._id?
      throw new Error 'inserted doc should not yet have an _id attribute'
    doc._id = LocalCollection.uuid()
    db.transaction(
      ((tx) =>
        tx.executeSql 'INSERT INTO documents (id, collection, document) VALUES (?, ?, ?)',
          [doc._id, @_name, JSON.stringify(doc)]
      ),
      ((error) =>
        # might be out of space?
        console.log 'insert transaction error', error
      ),
      (=>
        @_localCollection.insert(doc)
      )
    )
    doc._id

  find: (arg...) ->
    @_localCollection.find(arg...)

  update: (selector, modifier) ->
    unless _.isString(selector)
      throw new Error('not implemented yet')
    doc = null
    db.transaction(
      ((tx) =>
        tx.executeSql(
          'SELECT document FROM documents WHERE id=?',
          [selector],
          ((tx, result) =>
            return if result.rows.length isnt 1
            doc = JSON.parse(result.rows.item(0).document)
            LocalCollection._modify(doc, modifier)
            tx.executeSql(
              'UPDATE documents SET document=? WHERE id=?',
              [JSON.stringify(doc), doc._id],
            )
          )
        )
      ),
      ((error) => console.log 'modify transaction error', error),
      (=>
        if doc?
          @_localCollection.update doc._id, doc
          Meteor.LocalMsg.send 'Meteor.ClientCollection.single', @_name, doc._id
        else
          console.log 'but no document was found with id', selector
      )
    )

Meteor.ClientSQLCollection.erase = ->
  # TODO not good if other windows already have a collection open
  unless _.isEmpty(collections)
    throw new Error("call erase() before opening any collections")
  db.transaction(
    ((tx) -> tx.executeSql('DELETE FROM documents')),
    ((error) -> console.log 'erase transaction error', error),
    (-> console.log 'erase transaction success')
  )
