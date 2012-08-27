flo = require('../index').connect()
async = require 'async'
_ = require 'underscore'
assert = require 'assert'

module.exports =
  'test prefixes_for_phrase': () ->
    result = flo.prefixes_for_phrase("abc")
    assert.eql(["a", "ab", "abc"], result)

    result = flo.prefixes_for_phrase("abc abc")
    assert.eql(["a", "ab", "abc"], result)

    result = flo.prefixes_for_phrase("a(*&^%bc")
    assert.eql(["a", "ab", "abc"], result)

    result = flo.prefixes_for_phrase("how are you")
    assert.eql(["h","ho","how","a","ar","are","y","yo","you"], result)

  'test key': () ->
    result = flo.key("fun", "abc")
    assert.equal("flo:fun:abc", result)

  'test add_term': () ->
    term_type = 'book'
    term_id = 1
    term = "Algorithms for Noob"
    term_score = 10
    term_data =
      ISBN: "123AOU123"
      Publisher: "Siong Publication"
    flo.add_term(term_type, term_id, term, term_score, term_data, ->
      async.parallel([
        ((callback) ->
          flo.redis.hget flo.key(term_type, "data"), term_id, (err, reply) ->
            result = JSON.parse(reply)
            assert.equal(term, result.term)
            assert.equal(term_score, result.score)
            assert.eql(term_data, result.data)

            callback()
        ),
        ((callback) ->
          async.map flo.prefixes_for_phrase(term),
          ((w, cb) =>
            flo.redis.zrange flo.key(term_type, "index", w), 0, -1, cb# sorted set
          ),
          (err, results) ->
            assert.equal(17, results.length)
            results = _.uniq(_.flatten(results))
            assert.equal(1, results[0])
            callback()
        )
      ])
    )

  'test search_term': () ->
    venues = require('../samples/venues').venues
    async.series([
      ((callback) ->
        async.forEach venues,
        ((venue, cb) ->
          flo.add_term("venues", venue.id, venue.term, venue.score, venue.data, ->
            cb()
          )
        ), callback),
      ((callback) ->
        flo.search_term ["venues", "food"], "stadium",
        (err, results) ->
          assert.equal(3, results.venues.length)
          callback()
      ),
      ((callback) ->
        # set limit to 1
        flo.search_term ["venues"], "stadium", 1,
        (err, results) ->
          assert.equal(1, results.venues.length)
          callback()
      )
    ], () ->
      flo.end()
    )

  'test remove_term': () ->
    term_type = "foods"
    term_id = 2
    term = "Burger"
    term_score = 10
    term_data =
      temp:"data"

    all_data =
      id:term_id
      term:term
      score:term_score
      data:term_data

    async.series([
      ((callback) ->
        flo.add_term term_type, term_id, term, term_score, term_data, callback
      ),
      ((callback) ->
        flo.get_id term_type, term,
          (err, id) ->
            assert.isNull err
            assert.eql id, term_id
            callback()
      ),
      ((callback) ->
        flo.get_data term_type, term_id,
          (err, data) ->
            assert.isNull err
            assert.eql data, all_data
            callback()
      ),
      ((callback) ->
        flo.remove_term term_type, term_id, callback
      ),
      ((callback) ->
        flo.search_term [term_type], term,
          (err, result) ->
            eql =
              term: term
            eql[term_type] = []
            assert.eql result, eql
      )
    ], () ->
      flo.end()
    )