app = require('express').createServer()
flo = require('../index').connect()
async = require 'async'

app.get '/', (req, res) ->
  res.send('Up and running')

app.get '/search/:types/:term/:limit', (req, res) ->
  types = req.params.types.split(',')
  flo.search_term types, req.params.term, parseInt(req.params.limit), (err, results) ->
    res.send(JSON.stringify(results))

venues = require('../samples/venues').venues
async.forEach venues,
((venue, cb) ->
  flo.add_term("venues", venue.id, venue.term, venue.score, venue.data, ->
    cb()
  )
), ->
  app.listen(3000)

