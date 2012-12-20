return unless Meteor.isClient

# Meteor.ClientSQLCollection.erase()

count = new Meteor.ClientSQLCollection 'count', ->
  if count.find().count() is 0
    count.insert {i: 30}

window.count = count

Template.hello.events
  'click #inc': ->
    id = count.find().map((doc) -> doc._id)[0]
    count.update(id, {$inc: {i: 1}})

Template.hello.count = -> count.find({})
