// Generated by CoffeeScript 1.4.0
(function() {
  var count;

  if (!Meteor.isClient) {
    return;
  }

  count = new Meteor.BrowserCollection('count', function() {
    if (count.find().count() === 0) {
      return count.insert({
        i: 30
      });
    }
  });

  Template.hello.events({
    'click #inc': function() {
      return count.update({}, {
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
