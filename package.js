Package.describe({
  summary: "client collection"
});

Package.on_use(function (api) {
  api.use('localmsg', 'client');
  api.add_files(['client-collection.js'], 'client');
});
