// Generated by CoffeeScript 1.4.0
(function() {
  var collections, db, each_sql_result, result_as_array, _when,
    __slice = [].slice;

  _when = this.when;

  db = openDatabase('Meteor.BrowserCollection', '', '', 1024 * 1024, db);

  if (db.version === '') {
    db.changeVersion('', '1', (function(tx) {
      tx.executeSql('CREATE TABLE documents (\
           id TEXT NOT NULL PRIMARY KEY,\
           collection TEXT NOT NULL,\
           document TEXT NOT NULL\
         )\
        ');
      return tx.executeSql('CREATE INDEX collections ON documents (collection)');
    }), (function(error) {
      return console.log('create database error', error);
    }), (function() {
      return console.log('create database success');
    }));
  }

  collections = {};

  Meteor.BrowserMsg.listen({
    'Meteor.BrowserCollection.single': function(collection_name, doc_id) {
      var _ref;
      return (_ref = collections[collection_name]) != null ? _ref._reload_single(doc_id) : void 0;
    }
  });

  Meteor.BrowserSQLCollection = function(name, cb) {
    if (collections[name] != null) {
      throw new Error('a BrowserCollection with this name has already been created: ' + name);
    }
    this._name = name;
    this._localCollection = new LocalCollection();
    collections[name] = this;
    this._load(cb);
    return void 0;
  };

  each_sql_result = function(result, callback) {
    var i, _i, _ref, _results;
    _results = [];
    for (i = _i = 0, _ref = result.rows.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
      _results.push(callback(result.rows.item(i)));
    }
    return _results;
  };

  result_as_array = function(result) {
    var a, i, _i, _ref;
    a = [];
    for (i = _i = 0, _ref = result.rows.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
      a.push(result.rows.item(i));
    }
    return a;
  };

  _.extend(Meteor.BrowserSQLCollection.prototype, {
    _load: function(cb) {
      var _this = this;
      return db.transaction((function(tx) {
        return tx.executeSql('SELECT document FROM documents WHERE collection=?', [_this._name], (function(tx, result) {
          return each_sql_result(result, function(row) {
            return _this._localCollection.insert(JSON.parse(row.document));
          });
        }));
      }), (function(error) {
        return console.log(error);
      }), (function() {
        return typeof cb === "function" ? cb() : void 0;
      }));
    },
    _reload_single: function(doc_id) {
      var doc,
        _this = this;
      doc = null;
      return db.transaction((function(tx) {
        return tx.executeSql('SELECT document FROM documents WHERE collection=? AND id=?', [_this._name, doc_id], (function(tx, result) {
          if (result.rows.length === 1) {
            return doc = JSON.parse(result.rows.item(0).document);
          }
        }));
      }), (function(error) {
        return console.log(error);
      }), (function() {
        if (doc != null) {
          if (_this._localCollection.findOne(doc._id) != null) {
            return _this._localCollection.update(doc._id, doc);
          } else {
            return _this._localCollection.insert(doc);
          }
        } else {
          return _this._localCollection.remove(doc_id);
        }
      }));
    },
    insert: function(doc, callback) {
      var _this = this;
      if (doc._id != null) {
        throw new Error('inserted doc should not yet have an _id attribute');
      }
      doc._id = LocalCollection.uuid();
      db.transaction((function(tx) {
        return tx.executeSql('INSERT INTO documents (id, collection, document) VALUES (?, ?, ?)', [doc._id, _this._name, JSON.stringify(doc)]);
      }), (function(error) {
        return console.log('insert transaction error', error);
      }), (function() {
        _this._localCollection.insert(doc);
        Meteor.BrowserMsg.send('Meteor.BrowserCollection.single', _this._name, doc._id);
        return callback();
      }));
      return doc._id;
    },
    find: function() {
      var arg, _ref;
      arg = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return (_ref = this._localCollection).find.apply(_ref, arg);
    },
    findOne: function() {
      var arg, _ref;
      arg = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return (_ref = this._localCollection).findOne.apply(_ref, arg);
    },
    update: function(selector, modifier) {
      var doc,
        _this = this;
      if (!LocalCollection._selectorIsId(selector)) {
        throw new Error('not implemented yet');
      }
      doc = null;
      return db.transaction((function(tx) {
        return tx.executeSql('SELECT document FROM documents WHERE id=?', [selector], (function(tx, result) {
          if (result.rows.length !== 1) {
            return;
          }
          doc = JSON.parse(result.rows.item(0).document);
          LocalCollection._modify(doc, modifier);
          return tx.executeSql('UPDATE documents SET document=? WHERE id=?', [JSON.stringify(doc), doc._id]);
        }));
      }), (function(error) {
        return console.log('modify transaction error', error);
      }), (function() {
        if (doc != null) {
          _this._localCollection.update(doc._id, doc);
          return Meteor.BrowserMsg.send('Meteor.BrowserCollection.single', _this._name, doc._id);
        }
      }));
    },
    remove: function(selector) {
      var doc_id,
        _this = this;
      if (!LocalCollection._selectorIsId(selector)) {
        throw new Error('not implemented yet');
      }
      doc_id = selector;
      return db.transaction((function(tx) {
        return tx.executeSql('DELETE FROM documents WHERE id=?', [doc_id]);
      }), (function(error) {
        return console.log('remove transaction error', error);
      }), (function(tx, result) {
        _this._localCollection.remove(doc_id);
        return Meteor.BrowserMsg.send('Meteor.BrowserCollection.single', _this._name, doc_id);
      }));
    }
  });

  Meteor.BrowserSQLCollection.erase = function() {
    var done;
    done = _when.defer();
    if (!_.isEmpty(collections)) {
      throw new Error("call erase() before opening any collections");
    }
    db.transaction((function(tx) {
      return tx.executeSql('DELETE FROM documents');
    }), (function(error) {
      console.log('erase transaction error', error);
      return done.reject(error);
    }), (function() {
      console.log('erase transaction success');
      return done.resolve();
    }));
    return done.promise;
  };

  Meteor.BrowserSQLCollection.reset = function() {
    return collections = {};
  };

}).call(this);
