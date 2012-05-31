# **[flo](https://github.com/FLOChip/flo)** is an redis powered node.js autocompleter inspired by [soulmate](https://github.com/seatgeek/soulmate).
# You can check out some examples [here](https://github.com/FLOChip/flo/tree/master/examples).
_ = require "underscore"
async = require "async"

# Sets up a new Redis Connection.
#
# options - Optional Hash of options.
#
# * `redis`       - An existing redis connection to use.
# * `host`        - String Redis host.  (Default: Redis' default)
# * `port`        - Integer Redis port.  (Default: Redis' default)
# * `password`    - String Redis password.
# * `namespace`   - String namespace prefix for Redis keys.
#               (Default: flo).
# * `mincomplete` - Minimum completion of keys required for auto completion.
#               (Default: 1)
# * `database`    - Integer of the Redis database to select.
#
# Returns a Connection instance.
exports.connect = (options) ->
  new exports.Connection options || {}

# Handles the connection to the Redis server.
class Connection
  constructor: (options) ->
    @helper      = new Helper
    @redis       = options.redis       || connectToRedis options
    @namespace   = options.namespace   || 'flo'
    @mincomplete = options.mincomplete || 1
    @redis.select options.database if options.database?

  # Public: Get all prefixes for a phrase
  #
  # * `phrase` - the phrase that needs to be parsed into many prefixes
  #
  # Returns an array of unique prefixes for the phrase
  prefixes_for_phrase: (phrase) ->
    words = @helper.normalize(phrase).split(' ')
    _.uniq(
      _.flatten(
        _.map(words, (w) =>
          _.map([(@mincomplete-1)..(w.length-1)], (l) ->
            w[0..l]
          )
        )
      )
    )

  # Public: Search for a term
  #
  # * `types` - types of term that you are looking for (Array of String)
  # * `phrase` - the phrase or phrases you want to be autocompleted
  # * `limit` - the count of the number you want to return (optional, default: 5)
  # * `callback(err, result)` - err is the error and results is the results
  search_term: (types, phrase, args...) ->
    if typeof(args[0]) == 'number'
      limit = args[0]
    else
      limit = 5
    callback = args[args.length-1]

    async.map types, (type, callb) =>
      words = _.uniq(
        @helper.normalize(phrase).split(' ')
      ).sort()

      # for caching purpose
      cachekey = @key(type, "cache", words.join('|'))
      async.waterfall([
        ((next) =>
          @redis.exists cachekey, next
        ),
        ((exists, next) =>
          if !exists
            interkeys = (@key(type, "index", w) for w in words)
            @redis.zinterstore cachekey, interkeys.length, interkeys..., (err, count) =>
              # expire after 10 minutes
              @redis.expire cachekey, 10 * 60, -> next()
          else
            next()
        ),
        ((next) =>
          @redis.zrevrange cachekey, 0, (limit - 1), (err, ids) =>
            if ids.length > 0
              @redis.hmget @key(type, "data"), ids..., (err, matches) ->
                decoded_results = (JSON.parse match for match in matches)
                next(err, decoded_results)
            else
              next(null, [])
        )
      ], (err, results) ->
        data = {}
        data[type] = results
        callb(err, data)
      )
    , (err, termsets) ->
      results = {}
      results.results = _.extend termsets...
      results.term = phrase
      callback(err, results)

  # Public: Add a new term
  #
  # * `type`     - the type of data of this term (String)
  # * `id`       - unique identifier(within the specific type)
  # * `term`     - the phrase you wish to provide completions for
  # * `score`    - user specified ranking metric (redis will order things lexicographically for items with the same score)
  # * `data`     - container for metadata that you would like to return when this item is matched (optional)
  # * `callback` - callback to be run (optional)
  #
  # Returns nothing.
  add_term: (type, id, term, score, args...) ->
    if typeof(args[0]) != 'function'
      data = args[0]
      callback = args[args.length-1]
    else if typeof(args[0]) == 'function'
      callback = args[0]

    # store the data in parallel
    async.parallel([
      ((callb) =>
        @redis.hset @key(type, "data"), id,
          JSON.stringify id: id, term: term, score: score, data: (data || []),
          ->
            callb()
      ),
      ((callb) =>
        async.forEach @prefixes_for_phrase(term),
        ((w, cb) =>
          @redis.zadd @key(type, "index", w), score, id, # sorted set
          -> cb()
        ), ->
          callb()
      )
    ], ->
      callback() if callback?
    )

  # Public: Get the redis instance
  #
  # Returns the redis instance.
  redis: ->
    @redis

  # Public: Quits the connection to the Redis server.
  #
  # Returns nothing.
  end: ->
    @redis.quit()

  # Builds a namespaced Redis key with the given arguments.
  #
  # * `type` - Type of the param
  # * `args` - Array of Strings.
  #
  # Returns an assembled String key.
  key: (args...) ->
    args.unshift @namespace
    args.join ":"

class Helper
  # Public: Normalize a term to remove all other characters than a-z and 0-9.
  #
  # * `term` - the term to be normalized
  #
  # Returns a normalized term.
  normalize: (term) ->
    @strip(@gsub(term.toLowerCase(), /[^a-z0-9 ]/i, ''))

  # Public: This function partially simulates the Ruby's String gsub method.
  #
  # * `source` - the source string
  # * `pattern` - the Regex pattern
  # * `replacement` - the replacement text
  #
  # Example:
  #
  #     gsub("-abc-abc-", /[^a-z0-9 ]/i, '')  # returns "abcabc"
  #     gsub("-abc-abc-", /[^a-z0-9 ]/i, '*') # returns "*abc*abc*"
  #
  # Returns the modified string.
  gsub: (source, pattern, replacement) ->
    unless pattern? and replacement?
      return source

    result = ''
    while source.length > 0
      if (match = source.match(pattern))
        result += source.slice(0, match.index)
        result += replacement
        source  = source.slice(match.index + match[0].length)
      else
        result += source
        source = ''

    result

  # Public: Strip out leading and trailing whitespaces.
  #
  # * `source` - string to be stripped
  #
  # Returns a copy of str with leading and trailing whitespace removed.
  strip: (source) ->
    source.replace(/^\s+/, '').replace(/\s+$/, '')

connectToRedis = (options) ->
  redis = require('redis').createClient options.port, options.host
  redis.auth options.password if options.password?
  redis

exports.Helper = new Helper
exports.Connection = Connection
