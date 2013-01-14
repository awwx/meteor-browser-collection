BrowserCollection
=================

Experimental persistent local browser collections for Meteor,
reactively shared across browser tabs.

Meteor.BrowserCollection has a similar API to Meteor.Collection, but
is persistent, stored locally in the browser (using IndexedDB or Web
SQL Database storage), and is reactively shared across browser windows
in the same browser.

Browser collections do not use the Meteor server or the Internet, and
so can be used while offline.


Supported Browsers
------------------

Browsers need to support either
[IndexedDB](http://caniuse.com/#feat=indexeddb)
or
[Web SQL Database](http://caniuse.com/#feat=sql-storage),
and thus in theory should work with:

* Android 2.1+
* Chrome 23+
* Firefox 16+
* IE 10
* iOS Safari 3.2+
* Opera 12.1+
* Safari 5.1+

Tested so far with

* Android 2.3
* Chrome 23
* Firefox 18
* IE 10
* iOS Safari 5.1
* Safari 5


Safe Updates
------------

A primary goal is to make it safe to make updates in different windows
at the same time, such as

    collection.update(id, {$inc: {a: 1}});

or

    collection.update(id, {$push: {list: "foo"}});

To accomplish this the update algorithm carefully applies updates
entirely within a database transaction.  Although a cached copy of the
collection is kept in memory to support Meteor's Cursor API, the most
recent version of the document is read within the transaction:

    TRANSACTION(
      doc = read_doc_from_database()
      modify(doc)
      write_doc_to_database(doc)
    )

Without this two windows could both perform an update operation and have
one of them not be applied:

    window 1: doc = read_doc_from_database()  -- reads doc {i: 10}
    window 2: doc = read_doc_from_database()  -- reads doc {i: 10}
    window 1: modify(doc, {$inc: {i: 1}})     -- updates doc to {i: 11}
    window 2: modify(doc, {$inc: {i: 1}})     -- updates doc to {i: 11}
    window 1: write_doc_to_database(doc)      -- stores doc {i: 11}
    window 2: write_doc_to_database(doc)      -- stores doc {i: 11}


Optimizations
-------------

The only optimization currently performed is if `modify` is called
with a string selector (a document id), then only that document is
read for the update; otherwise the entire collection of documents is
retrieved for each update.


Differences with Meteor Collections
-----------------------------------

Unlike Meteor.Collection, updates are *not* applied to the local
collection before being stored in the browser database.  With a
Meteor.Collection, code will see local updates immediately:

    var id = collection.insert({a: 1, b: 2});
    var doc = collection.findOne(id);

but with a browser collection code won't see the update until the
update has been performed:

    browserCollection.insert({a: 1, b: 2}, function (err, id) {
      var doc = collection.findOne(id);
    });


API
---

    new Meteor.BrowserCollection(name, [callback])

Creates and returns a BrowserCollection named `name`.  The name is
required.  The optional callback is called when the collection has
been populated from the browser's database.


    collection.find(selector, [options])
    collection.findOne(selector, [options])

Works the same as Meteor.Collection, and returns a
Meteor.Collection.Cursor.


    collection.insert(doc, [callback])

The optional callback will be called after the document has been
inserted.


    collection.update(selector, modifier, [options], [callback])

Optimized if `selector` is a string (a document id).


    collection.remove(selector, [callback])

Optimized if `selector` is a string (a document id).


The server API methods `allow` and `deny` are not present.
