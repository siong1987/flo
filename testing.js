var redis = require("redis"),
    client = redis.createClient(),
    async = require("async");

redis.debug_mode = true;

client.on("connect", function () {
  var venues = ['chicago', 'new york'];
  async.forEach(venues, (function(venue, cb) {
    client.zadd("stadium", 1, venue, function() {
      cb();
    });
  }), function() {
    client.exists('abc', function(err, exist) {
      console.log("exists: " + exist);
      client.zrange("stadium", 0, -1, function(err, results) {
        console.log("results: " + results);
      });
    });
  });
});