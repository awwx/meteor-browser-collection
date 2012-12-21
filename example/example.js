// Generated by CoffeeScript 1.4.0
(function() {
  var count;

  if (!Meteor.isClient) {
    return;
  }

  count = new Meteor.BrowserSQLCollection('count', function() {
    if (count.find().count() === 0) {
      return count.insert({
        i: 30
      });
    }
  });

  window.count = count;

  Template.hello.events({
    'click #inc': function() {
      var id;
      id = count.find().map(function(doc) {
        return doc._id;
      })[0];
      return count.update(id, {
        $inc: {
          i: 1
        }
      });
    }
  });

  Template.hello.count = function() {
    return count.find({});
  };

}).call(this);