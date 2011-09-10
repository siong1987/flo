(function() {
  var Connection, Helper, async, connectToRedis, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; }, __slice = Array.prototype.slice;
  _ = require("underscore");
  async = require("async");
  exports.connect = function(options) {
    return new exports.Connection(options || {});
  };
  Connection = (function() {
    function Connection(options) {
      this.helper = new Helper;
      this.redis = options.redis || connectToRedis(options);
      this.namespace = options.namespace || 'flo';
      this.mincomplete = options.mincomplete || 1;
      if (options.database != null) {
        this.redis.select(options.database);
      }
    }
    Connection.prototype.prefixes_for_phrase = function(phrase) {
      var words;
      words = this.helper.normalize(phrase).split(' ');
      return _.uniq(_.flatten(_.map(words, __bind(function(w) {
        var _i, _ref, _ref2, _results;
        return _.map((function() {
          _results = [];
          for (var _i = _ref = this.mincomplete - 1, _ref2 = w.length - 1; _ref <= _ref2 ? _i <= _ref2 : _i >= _ref2; _ref <= _ref2 ? _i++ : _i--){ _results.push(_i); }
          return _results;
        }).apply(this, arguments), function(l) {
          return w.slice(0, (l + 1) || 9e9);
        });
      }, this))));
    };
    Connection.prototype.search_term = function() {
      var args, callback, limit, phrase, types;
      types = arguments[0], phrase = arguments[1], args = 3 <= arguments.length ? __slice.call(arguments, 2) : [];
      if (typeof args[0] === 'number') {
        limit = args[0];
      } else {
        limit = 5;
      }
      callback = args[args.length - 1];
      return async.map(types, __bind(function(type, callb) {
        var cachekey, words;
        words = _.uniq(this.helper.normalize(phrase).split(' ')).sort();
        cachekey = this.key(type, "cache", words.join('|'));
        return async.waterfall([
          (__bind(function(cb) {
            return this.redis.exists(cachekey, cb);
          }, this)), (__bind(function(exists, cb) {
            var interkeys, _ref;
            if (!exists) {
              interkeys = _.map(words, __bind(function(w) {
                return this.key(type, "index", w);
              }, this));
              return (_ref = this.redis).zinterstore.apply(_ref, [cachekey, interkeys.length].concat(__slice.call(interkeys), [__bind(function(err, count) {
                return this.redis.expire(cachekey, 10 * 60, function() {
                  return cb();
                });
              }, this)]));
            } else {
              return cb();
            }
          }, this)), (__bind(function(cb) {
            return this.redis.zrevrange(cachekey, 0, limit - 1, __bind(function(err, ids) {
              var _ref;
              if (ids.length > 0) {
                return (_ref = this.redis).hmget.apply(_ref, [this.key(type, "data")].concat(__slice.call(ids), [cb]));
              } else {
                return cb(null, []);
              }
            }, this));
          }, this))
        ], function(err, results) {
          var data;
          data = {};
          data[type] = results;
          return callb(err, data);
        });
      }, this), function(err, results) {
        results = _.extend.apply(_, results);
        results.term = phrase;
        return callback(err, results);
      });
    };
    Connection.prototype.add_term = function(type, id, term, score, data, callback) {
      return async.parallel([
        (__bind(function(callb) {
          return this.redis.hset(this.key(type, "data"), id, JSON.stringify({
            id: id,
            term: term,
            score: score,
            data: data || []
          }), function() {
            return callb();
          });
        }, this)), (__bind(function(callb) {
          return async.forEach(this.prefixes_for_phrase(term), (__bind(function(w, cb) {
            return this.redis.zadd(this.key(type, "index", w), score, id, function() {
              return cb();
            });
          }, this)), function() {
            return callb();
          });
        }, this))
      ], function() {
        if (callback != null) {
          return callback();
        }
      });
    };
    Connection.prototype.redis = function() {
      return this.redis;
    };
    Connection.prototype.end = function() {
      return this.redis.quit();
    };
    Connection.prototype.key = function() {
      var args;
      args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      args.unshift(this.namespace);
      return args.join(":");
    };
    return Connection;
  })();
  Helper = (function() {
    function Helper() {}
    Helper.prototype.normalize = function(term) {
      return this.strip(this.gsub(term.toLowerCase(), /[^a-z0-9 ]/i, ''));
    };
    Helper.prototype.gsub = function(source, pattern, replacement) {
      var match, result;
      if (!((pattern != null) && (replacement != null))) {
        return source;
      }
      result = '';
      while (source.length > 0) {
        if ((match = source.match(pattern))) {
          result += source.slice(0, match.index);
          result += replacement;
          source = source.slice(match.index + match[0].length);
        } else {
          result += source;
          source = '';
        }
      }
      return result;
    };
    Helper.prototype.strip = function(source) {
      return source.replace(/^\s+/, '').replace(/\s+$/, '');
    };
    return Helper;
  })();
  connectToRedis = function(options) {
    var redis;
    redis = require('redis').createClient(options.port, options.host);
    if (options.password != null) {
      redis.auth(options.password);
    }
    return redis;
  };
  exports.Helper = new Helper;
  exports.Connection = Connection;
}).call(this);
