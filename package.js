Package.describe({
  summary: "browser collection"
});

Package.on_use(function (api) {
  api.use('browser-msg', 'client');
  api.use('random', 'client');
  api.use('when', 'client');
  api.add_files(['browser-collection.js'], 'client');
});
