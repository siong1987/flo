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

    async.map types, (type, callback) =>
      words = _.uniq(
        @helper.normalize(phrase).split(' ')
      ).sort()

      # for caching purpose
      cachekey = @key(type, "cache", words.join('|'))
      async.waterfall([
        ((callback) =>
          @redis.exists cachekey, callback
        ),
        ((exists, callback) =>
          if !exists
            interkeys = _.map(words, (w) =>
              @key(type, "index", w)
            )
            @redis.zinterstore cachekey, interkeys.length, interkeys..., (err, count) =>
              @redis.expire cachekey, 10 * 60, -> # expire after 10 minutes
                callback()
          else
            callback()
        ),
        ((callback) =>
          @redis.zrevrange cachekey, 0, (limit - 1), (err, ids) =>
            if ids.length > 0
              @redis.hmget @key(type, "data"), ids..., callback
            else
              callback(null, [])
        )
      ], (err, results) ->
        data = {}
        data[type] = results
        callback(err, data)
      )
    , (err, results) ->
      results = _.extend results...
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
      ((callback) =>
        @redis.hset @key(type, "data"), id,
          JSON.stringify id: id, term: term, score: score, data: (data || []),
          ->
            callback()
      ),
      ((callback) =>
        async.forEach @prefixes_for_phrase(term),
        ((w, callback) =>
          @redis.zadd @key(type, "index", w), score, id, callback # sorted set
        ), callback
      ),
      ((callback) =>
        key = @key(type, @helper.normalize(term))
        # do we already have this term?
        @redis.get key, (err, result) =>
          if (err)
            return callback(err)

          if (result)
            # append to existing ids (without duplicates)
            arr = JSON.parse(result)
            arr.push(id)
            arr = _.uniq(arr)
          else
            # create new array
            arr = [id]

          # store the id
          @redis.set key, JSON.stringify(arr), callback
      )
    ], ->
      callback() if callback?
    )

  # Public: Remove a term
  #
  # * `type`     - the type of data of this term (String)
  # * `id`       - unique identifier (within the specific type)
  # * `callback(err)` - callback to be run (optional)
  #
  # Returns nothing.
  remove_term: (type, id, callback) ->
    #get the term
    @redis.hget @key(type, "data"), id,
      (err, result) =>
        if err
          return callback(err)
        if result == null
          return callback(new Error("Invalid term id: "+ id))

        term = JSON.parse(result).term

        # remove 
        async.parallel([
          ((callback) =>
            @redis.hdel @key(type, "data"), id, callback
          ),
          ((callback) =>
            async.forEach @prefixes_for_phrase(term),
            ((w, callback) =>
              @redis.zrem @key(type, "index", w), id, callback
            ), callback
          ),
          ((callback) =>
            key = @key(type, @helper.normalize(term))
            @redis.get key, (err, result) =>
              if (err)
                return callback(err)

              if (result == null)
                return callback(new Error("Couldn't delete #{id}. No such entry."))

              arr = JSON.parse(result)

              if (arr.toString() == [id].toString())
                # delete it cause there's nothing left
                return @redis.del key, callback

              # remove from array
              @redis.set key, JSON.stringify(_.without(arr, id)), callback
          )
        ], (err) ->
          callback(err) if callback?
        )

  # Public: Returns an array of IDs for a term
  
  # * 'type'    - the type of data for this term
  # * 'term'    - the term to find the unique identifiers for
  # * 'callback(err, result)' - result is the ID for the term
  
  # Returns nothing.
  get_ids: (type, term, callback) ->
    @redis.get @key(type, @helper.normalize(term)), (err, result) ->
      if (err)
        return callback(err)

      arr = JSON.parse(result)

      if (arr == null)
        return callback(null, [])

      callback(null, arr)


  # Public: Returns the data for an ID
  
  # * 'type'    - the type of data for this term
  # * `id`       - unique identifier (within the specific type)
  # * 'callback(err, result)' - result is the data
  
  # Returns nothing.
  get_data: (type, id, callback) ->
    @redis.hget @key(type, "data"), id, (err, result) ->
      if err
        return callback(err)

      callback(null, JSON.parse(result))

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


  constructor: ->
    # Store array of latin lower case special characters and their normal equivalent
    # Also replace $ with s
    @latinChars = [
      ["a",/[\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5\u0101\u0103\u0105\u01CE\u01DF\u01E1\u01FB\u0201\u0203\u0227\u0250\u0251\u0252]/g],
      ["b",/[\u0180\u0183\u0185\u0253\u0299]/g],
      ["ae",/[\u00E6\u01E3\u01FD]/g],
      ["c",/[\u00E7\u0107\u0109\u010B\u010D\u0188\u023C\u0255]/g],
      ["d",/[\u010F\u0111\u018C\u0256\u0257]/g],
      ["e",/[\u00E8\u00E9\u00EA\u00EB\u0113\u0115\u0117\u0119\u011B\u01DD\u0205\u0207\u0229\u0247\u0258\u0259\u025A\u025B\u025C\u025D\u025E]/g],
      ["f",/[\u0192]/g],
      ["g",/[\u011D\u011F\u0121\u0123\u01E5\u01E5\u01F5\u0260\u0261\u0262\u029B]/g],
      ["h",/[\u0125\u0127\u021F\u0265\u0266\u0267\u029C]/g],
      ["i",/[\u00EC\u00ED\u00EE\u00EF\u0129\u012B\u012D\u012F\u0131\u01D0\u0209\u020B\u0268\u026A]/g],
      ["j",/[\u01F0\u0237\u0249\u025F\u0284\u029D]/g],
      ["k",/[\u0137\u0138\u0199\u01E9\u029E]/g],
      ["l",/[\u013A\u013C\u013E\u0140\u0142\u019A\u0234\u026B\u026C\u026D\u029F]/g],
      ["m",/[\u026F\u0270\u0271]/g],
      ["n",/[\u00F1\u0144\u0146\u0148\u0149\u014B\u019E\u01F9\u0235\u0272\u0273\u0274]/g],
      ["o",/[\u00F0\u014D\u014F\u0151\u00F2\u00F3\u00F4\u00F5\u00F6\u00F8\u01A1\u01D2\u01EB\u01ED\u01FF\u020D\u020F\u022B\u022D\u022F\u0231\u0254\u0275]/g],
      ["oe",/[\u0153\u0276]/g],
      ["p",/[\u01A5]/g],
      ["q",/[\u024B\u02A0]/g],
      ["r",/[\u0155\u0157\u0159\u0211\u0213\u024D\u0279\u027A\u027B\u027C\u027D\u027E\u027F\u0280\u0281]/g],
      ["s",/[\$\u015B\u015D\u015F\u0161\u0219\u023F\u0282]/g],
      ["t",/[\u0163\u0165\u0167\u01AB\u01AD\u021B\u0236\u0287\u0288]/g],
      ["u",/[\u00F9\u00FA\u00FB\u00FC\u0169\u016B\u016D\u016F\u0171\u0173\u01B0\u01D4\u01D6\u01D8\u01DA\u01DC\u0215\u0217\u0289\u028A]/g],
      ["v",/[\u028B\u028C]/g],
      ["w",/[\u0175\u028D]/g],
      ["y",/[\u00FD\u00FF\u0177\u01B4\u0233\u024F\u028E\u028F]/g],
      ["z",/[\u017A\u017C\u017E\u01B6\u0225\u0240\u0290\u0291]/g]]

  # Public: Normalize a term to remove all other characters than a-z and 0-9.
  #
  # * `term` - the term to be normalized
  #
  # Returns a normalized term.
  normalize: (term) ->
    @strip(@replaceLatin(term.toLowerCase()).replace(/[^a-z0-9 ]/gi, ''))

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


  # Public: Replace special latin characters with their root letter.
  #
  # * `term` - string to be replaced
  #
  # Returns term with special characters replaced
  replaceLatin: (term) ->

    for translation in @latinChars
      do (translation) ->
        term = term.replace(translation[1], translation[0])

    term


connectToRedis = (options) ->
  redis = require('redis').createClient options.port, options.host
  redis.auth options.password if options.password?
  redis

exports.Helper = new Helper
exports.Connection = Connection
