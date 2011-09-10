(function() {
  var app, async, flo, venues;
  app = require('express').createServer();
  flo = require('../index').connect();
  async = require('async');
  app.get('/', function(req, res) {
    return res.send('Up and running');
  });
  app.get('/search/:types/:term/:limit', function(req, res) {
    var types;
    types = req.params.types.split(',');
    return flo.search_term(types, req.params.term, parseInt(req.params.limit), function(err, results) {
      return res.send(JSON.stringify(results));
    });
  });
  venues = require('../samples/venues').venues;
  async.forEach(venues, (function(venue, cb) {
    return flo.add_term("venues", venue.id, venue.term, venue.score, venue.data, function() {
      return cb();
    });
  }), function() {
    return app.listen(3000);
  });
}).call(this);
