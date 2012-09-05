flo
===
**flo** is a [redis](http://redis.io) powered [node.js](http://nodejs.org) autocompleter inspired by [soulmate](https://github.com/seatgeek/soulmate). You can use this anywhere you want since this is just a module. If you look into the examples folder, I have provided an example on how to get it work with [express](http://expressjs.com/).

If you want see a real world example of this, you should try out the search box at [SeatGeek](http://seatgeek.com) or [Quora](http://quora.com).

Documentations
==============

First, connect to the redis instance:

Sets up a new Redis Connection.

    var flo = require('flo').connect();

options - Optional Hash of options.

* `redis`       - An existing redis connection to use.
* `host`        - String Redis host. (Default: Redis' default)
* `port`        - Integer Redis port. (Default: Redis' default)
* `password`    - String Redis password.
* `namespace`   - String namespace prefix for Redis keys. (Default: flo).
* `mincomplete` - Minimum completion of keys required for auto completion. (Default: 1)
* `database`    - Integer of the Redis database to select.

Returns a Connection instance.

These are the public functions:

Add a new term
--------------

`add_term(type, id, term, score, data, callback)`:

* `type`     - the type of data of this term (String)
* `id`       - unique identifier(within the specific type)
* `term`     - the phrase you wish to provide completions for
* `score`    - user specified ranking metric (redis will order things lexicographically for items with the same score)
* `data`     - container for metadata that you would like to return when this item is matched (optional)
* `callback` - callback to be run (optional)

Returns nothing.

Search for a term
-----------------

`search_term(types, phrase, limit, callback)`:

* `types` - types of term that you are looking for (Array of String)
* `phrase` - the phrase or phrases you want to be autocompleted
* `limit` - the count of the number you want to return (optional, default: 5)
* `callback(err, result)` - err is the error and results is the results

This call:

`search_term(["chinese", "indian"], "rice", 1, cb);`

will return a result in json format like:

    {
      term: "rice"
      chinese: [
          {
            id: 3,
            term: "mongolian fried rice",
            score: 10,
            data: {
              name: "Gonghu Chinese Restaurant",
              address: "304, University Avenue, Palo Alto"
            }
          }
        ],
       indian: [
          {
            id: 1,
            term: "Briyani Chicken Rice",
            score: 5,
            data: {
              name: "Bombay Grill",
              address: "100 Green St, Urbana"
            }
          }
        ]
    }

Remove a term
-------------

`remove_term(type, id, callback)`:

* `type`     - the type of data of this term (String)
* `id`       - unique identifier(within the specific type)
* `callback` - callback to be run (optional)

Returns nothing.

Get the IDs for a term
----------------------

`get_ids (type, term, callback)`:

* `type`    - the type of data for this term
* `term`    - the term to find the unique identifiers for
* `callback(err, result)` - result is an array of IDs for the term.  Empty array if none were found

Get the data for an ID
-----------------------

`get_data(type, id, callback)`:

* `type`    - the type of data for this term
* `id`       - unique identifier (within the specific type)
* `callback(err, result)` - result is the data

For more information, you can read it [here](https://github.com/siong1987/flo/tree/master/docs).

## Tests
To run tests, first make sure your local redis is running, then:

    ./node_modules/expresso/bin/expresso test/*.test.js

### License
[MIT License](https://github.com/siong1987/flo/blob/master/LICENSE)

---
### Author
[Teng Siong Ong](https://github.com/siong1987/)

### Company
[FLOChip](http://flochip.com)
