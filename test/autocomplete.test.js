(function() {
  var assert, async, flo, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  flo = require('../index').connect();
  async = require('async');
  _ = require('underscore');
  assert = require('assert');
  module.exports = {
    'test prefixes_for_phrase': function() {
      var result;
      result = flo.prefixes_for_phrase("abc");
      assert.eql(["a", "ab", "abc"], result);
      result = flo.prefixes_for_phrase("abc abc");
      assert.eql(["a", "ab", "abc"], result);
      result = flo.prefixes_for_phrase("a(*&^%bc");
      assert.eql(["a", "ab", "abc"], result);
      result = flo.prefixes_for_phrase("how are you");
      return assert.eql(["h", "ho", "how", "a", "ar", "are", "y", "yo", "you"], result);
    },
    'test key': function() {
      var result;
      result = flo.key("fun", "abc");
      return assert.equal("flo:fun:abc", result);
    },
    'test add_term': function() {
      var term, term_data, term_id, term_score, term_type;
      term_type = 'book';
      term_id = 1;
      term = "Algorithms for Noob";
      term_score = 10;
      term_data = {
        ISBN: "123AOU123",
        Publisher: "Siong Publication"
      };
      return flo.add_term(term_type, term_id, term, term_score, term_data, function() {
        return async.parallel([
          (function(callback) {
            return flo.redis.hget(flo.key(term_type, "data"), term_id, function(err, reply) {
              var result;
              result = JSON.parse(reply);
              assert.equal(term, result.term);
              assert.equal(term_score, result.score);
              assert.eql(term_data, result.data);
              return callback();
            });
          }), (function(callback) {
            return async.map(flo.prefixes_for_phrase(term), (__bind(function(w, cb) {
              return flo.redis.zrange(flo.key(term_type, "index", w), 0, -1, cb);
            }, this)), function(err, results) {
              assert.equal(17, results.length);
              results = _.uniq(_.flatten(results));
              assert.equal(1, results[0]);
              return callback();
            });
          })
        ]);
      });
    },
    'test search_term': function() {
      var venues;
      venues = require('../samples/venues').venues;
      return async.series([
        (function(callback) {
          return async.forEach(venues, (function(venue, cb) {
            return flo.add_term("venues", venue.id, venue.term, venue.score, venue.data, function() {
              return cb();
            });
          }), callback);
        }), (function(callback) {
          return flo.search_term(["venues", "food"], "stadium", function(err, results) {
            console.log(results);
            assert.equal(3, results.venues.length);
            return callback();
          });
        }), (function(callback) {
          return flo.search_term(["venues"], "stadium", 1, function(err, results) {
            assert.equal(1, results.venues.length);
            return callback();
          });
        })
      ], function() {
        return flo.end();
      });
    }
  };
}).call(this);
