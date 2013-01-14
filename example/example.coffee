return unless Meteor.isClient

count = new Meteor.BrowserCollection 'count', ->
  if count.find().count() is 0
    count.insert {i: 30}

Template.hello.events
  'click #inc': ->
    count.update({}, {$inc: {i: 1}})

Template.hello.count = -> count.find({})
