testHelper = require('./test_helper')
should = require('should')
redisExpLock = require('../lib/redis_exp_lock')

# Redis client for testing. We'll create this asglobal here because mocha's
# before() doesn't provide a this-scope that is accessible by the actual examples.
#
# You can override the default connection by filling out PROJECT/test/redis.json.
# See PROJECT/test/redis.sample.json for an example.
redisClient = testHelper.getRedisClient()
withLock = redisExpLock(redis: redisClient)

describe 'redisExpLock', () ->

  beforeEach (done) ->
    # Reset lock state for every case
    redisClient.flushdb done

  describe 'when the lock has already been acquired', () ->

    beforeEach () ->
      withLock 'testLock', (err, retries, critSecDone) -> # This lock should never relenquish. Don't call critSecDone here.

    it 'should prevent other clients from acquiring the lock', (done) ->
      withLock 'testLock', (err, retries, critSecDone) ->
        should.exist err
        done()

    it 'the retry count should equal the maximum number of retries', (done) ->
      retries = 5
      withLock 'testLock', {maxRetries: retries}, (err, retries, critSecDone) ->
        should.exist err
        retries.should.eql retries
        done()

  it 'should allow other clients to acquire the lock after a release', (done) ->
    # First lock acquisition
    withLock 'testLock', (err, retries, critSecDone) ->
      unless err
        # Immediately release the lock
        critSecDone (err, result) ->
          unless err
            # Acquire the lock again after the release finishes
            withLock 'testLock', (err, retries, critSecDone) ->
              unless err
                should.not.exist err
                retries.should.eql 0
                done()

  describe 'expiration cases', () ->

    firstLockLifetime = 50

    beforeEach () ->
      withLock 'testLock', {lifetime: firstLockLifetime}, (err, retries, critSecDone) -> # This lock should never relenquish. Don't call critSecDone here.

    it 'should acquire the lock if the lifetime has elapsed', (done) ->
      setTimeout () ->
        withLock 'testLock', (err, retries, critSecDone) ->
          should.not.exist err
          retries.should.eql 0
          done()
      , firstLockLifetime + 10

    it 'should resolve lock contention with only a single winner', (done) ->
      # Create a several contending locks
      contenders = 10
      successes = 0
      failures = 0
      finished = 0

      retryTimeout = 5
      lockOpts =
        retryTimeout: retryTimeout
        maxRetries: (firstLockLifetime / retryTimeout) + 2

      for i in [0...contenders] by 1
        withLock 'testLock', lockOpts, (err, retries, critSecDone) ->
          if err
            # Contenders that fail
            failures += 1
            retries.should.eql lockOpts.maxRetries
          else
            successes += 1
            (retries > 0).should.be.true

          finished += 1
          if finished == contenders
            successes.should == 1
            failures.should == contenders - 1
            done()