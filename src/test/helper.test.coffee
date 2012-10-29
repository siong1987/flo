helper = require('../index').Helper
assert = require 'assert'

module.exports =
  'test strip': () ->
    assert.equal("abc", helper.strip(" abc"))
    assert.equal("abc", helper.strip("abc "))
    assert.equal("abc", helper.strip("  abc  "))

  'test gsub': () ->
    assert.equal("abcabc", helper.gsub("-abc-abc-", /[^a-z0-9 ]/i, ''))
    assert.equal("*abc*abc*", helper.gsub("-abc-abc-", /[^a-z0-9 ]/i, '*'))
    assert.equal("abcabc", helper.gsub("!@#abc-!@#abc!@#", /[^a-z0-9 ]/i, ''))

  'test gsub with errors': () ->
    # missing arguments should just return false
    assert.equal("-abc-abc-", helper.gsub("-abc-abc-"))
    assert.equal("-abc-abc-", helper.gsub("-abc-abc-", //))

  'test normalize': () ->
    assert.equal("abc", helper.normalize("a-bc"))
    assert.equal("a bc", helper.normalize("a bc"))
    assert.equal("absc", helper.normalize("a-b!@#$%^&*()c"))

