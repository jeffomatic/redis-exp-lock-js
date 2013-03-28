_ = require('underscore')
should = require('should')
Shavaluator = require('shavaluator')
testHelper = require('./test_helper')

# Redis client for testing. We'll create this asglobal here because mocha's
# before() doesn't provide a this-scope that is accessible by the actual examples.
#
# You can override the default connection by filling out PROJECT/test/redis.json.
# See PROJECT/test/redis.sample.json for an example.
redisClient = null
shavaluator = new Shavaluator
shavaluator.add require('../lib/redis_lua')

describe 'Lua scripts for redisExpLock', () ->

  before () ->
    redisClient = testHelper.getRedisClient()
    shavaluator.redis = redisClient

  beforeEach (done) ->
    redisClient.flushdb done

  describe 'setnx_pexpire', () ->

    ttl = 50

    describe "with key that hasn't been set yet", ->

      it 'returns 1 for keys the do not yet exist', (done) ->
        shavaluator.setnx_pexpire { keys: 'testKey', args: ['testValue', ttl] },
          (err, result) ->
            result.should.eql 1
            done()

      it 'sets the expiration correctly', (done) ->
        shavaluator.setnx_pexpire { keys: 'testKey', args: ['testValue', ttl] },
          (err, result) ->
            redisClient.pttl 'testKey', (err, result) ->
              result.should.not.be.below 0
              result.should.not.be.above ttl
              done()

    describe "with key that already exists", (done) ->

      beforeEach (done) ->
        redisClient.set 'testKey', 'testValue', (err, result) ->
          done()

      it 'does not set the key', (done) ->
        shavaluator.setnx_pexpire { keys: 'testKey', args: ['newValue', ttl] },
          (err, result) ->
            result.should.eql 0
            done()

      it 'does not set an expiration time', (done) ->
        redisClient.pttl 'testKey', (err, result) ->
          result.should.eql -1
          done()

  describe 'delequal', () ->

    beforeEach (done) ->
      redisClient.set 'testKey', 'matchThis', done

    it 'returns zero if the key does not exist', (done) ->
      shavaluator.delequal { keys: 'nonexistent', args: '1' }, (err, result) ->
        should.not.exist err
        result.should.eql 0
        done()

    describe 'when using a matching argument value', () ->

      beforeEach (done) ->
        shavaluator.delequal { keys: 'testKey', args: 'matchThis' }, (err, result) =>
          @err = err
          @result = result
          done()

      it 'should return 1', () ->
        should.not.exist @err
        @result.should.eql 1

      it 'should remove the key', (done) ->
        redisClient.get 'testKey', (err, result) ->
          should.not.exist err
          should.not.exist result
          done()

    describe 'when using a non-matching argument value', (done) ->

      beforeEach (done) ->
        shavaluator.delequal { keys: 'testKey', args: 'doesNotMatch' }, (err, result) =>
          @err = err
          @result = result
          done()

      it 'should return zero', () ->
        should.not.exist @err
        @result.should.eql 0

      it 'should not remove the key', (done) ->
        redisClient.get 'testKey', (err, result) ->
          should.not.exist err
          result.should.eql 'matchThis'
          done()
