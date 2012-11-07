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

    # result = flo.prefixes_for_phrase("a(*&^%bc")
    # assert.eql(["a", "ab", "abc"], result)

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
    ])

  'test remove_term': () ->
    term_type = "foods"
    term_id = 2
    term_id2 = 3
    term_id3 = 4
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
      ((next) ->
        flo.add_term term_type, term_id, term, term_score, term_data, next
      ),
      ((next) ->
        flo.get_ids term_type, term,
          (err, ids) ->
            assert.isNull err
            assert.eql ids, [term_id]
            next()
      ),
      ((next) ->
        flo.get_data term_type, term_id,
          (err, data) ->
            assert.isNull err
            assert.eql data, all_data
            next()
      ),
      ((next) ->
        # add a duplicate with new id
        flo.add_term term_type, term_id2, term, term_score, term_data, next
      ),
      ((next) ->
        # check to see if we get both ids back
        flo.get_ids term_type, term,
          (err, ids) ->
            assert.isNull err
            assert.eql ids, [term_id, term_id2]
            next()
      ),
      ((next) ->
        # add a third duplicate with new id
        flo.add_term term_type, term_id3, term, term_score, term_data, next
      ),
      ((next) ->
        # remove second
        flo.remove_term term_type, term_id2, next
      ),
      ((next) ->
        # remove first
        flo.remove_term term_type, term_id, next
      ),
      ((next) ->
        # check to see that the third is still in there
        flo.get_ids term_type, term,
          (err, ids) ->
            assert.eql ids, [term_id3]
            next()
      ),
      ((next) ->
        # remove third
        flo.remove_term term_type, term_id3, next
      ),
      ((next) ->
        # should return an error cause there are no more terms to remove
        flo.remove_term term_type, term_id,
          (err) ->
            assert.isNotNull(err)
            next()
      ),
      ((next) ->
        # should return empty array (no more terms)
        flo.get_ids term_type, term,
          (err, ids) ->
            assert.eql ids, []
            next()
      ),
      ((next) ->
        # should return no results
        flo.search_term [term_type], term,
          (err, result) ->
            eql =
              term: term
            eql[term_type] = []
            assert.eql result, eql
            next()
      )
    ], (err, results) ->
      flo.end()
    )
