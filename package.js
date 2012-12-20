Package.describe({
  summary: "client collection"
});

Package.on_use(function (api) {
  api.add_files(['client-collection.js'], 'client');
});
