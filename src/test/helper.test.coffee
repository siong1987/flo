helper = require('../index').Helper
assert = require 'assert'

module.exports =
  'test strip': () ->
    result = helper.strip(" abc")
    assert.equal("abc", result)

    result = helper.strip("abc ")
    assert.equal("abc", result)

    result = helper.strip("  abc  ")
    assert.equal("abc", result)

  'test gsub': () ->
    result = helper.gsub("-abc-abc-", /[^a-z0-9 ]/i, '')
    assert.equal("abcabc", result)

    result = helper.gsub("-abc-abc-", /[^a-z0-9 ]/i, '*')
    assert.equal("*abc*abc*", result)

    result = helper.gsub("!@#abc-!@#abc!@#", /[^a-z0-9 ]/i, '')
    assert.equal("abcabc", result)

  'test gsub with errors': () ->
    # missing arguments should just return false
    result = helper.gsub("-abc-abc-")
    assert.equal("-abc-abc-", result)

    result = helper.gsub("-abc-abc-", //)
    assert.equal("-abc-abc-", result)

  'test normalize': () ->
    normalized_str = helper.normalize("a-bc")
    assert.equal("abc", normalized_str)

    normalized_str = helper.normalize("a bc")
    assert.equal("a bc", normalized_str)

    normalized_str = helper.normalize("a-b!@#$%^&*()c")
    assert.equal("abc", normalized_str)

