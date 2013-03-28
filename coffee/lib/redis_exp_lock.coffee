_ = require('underscore')
uuid = require('uuid')
Shavaluator = require('shavaluator')
luaCommands = require('./redis_lua')

defaultConfig =
  lifetime: 1000
  retryTimeout: 5
  maxRetries: 0

# @opts {object} Options:
# - redis {option} The redis client
# - lifetime {number} Default expiration time
# - retryTimeout {number} Milliseconds to wait before re-attempting lock acquisition
# - maxRetries {number} Number of times to re-attempt acquisition before issuing an error
module.exports = (opts) ->

  config = _.extend {}, defaultConfig, opts

  # This returns a lock function configured using the given options. Usage:
  #
  # @key {string} key A string key to lock
  # @lockOpts {object, optional} Options for overriding the base configuration.
  # @callback {function} A callback representing a) an error handler, in case of
  #   a lock acquisition error, and b) the critical section. This callback
  #   should itself receive three parameters:
  #     1. An error object, in case there is lock acquisition error. This will
  #        be null if the lock is acquired successfully.
  #     2. A number representing the number of times lock acquisition was
  #        *retried*. Useful for determining if there was any contention. This
  #        is passed to the callback whether lock acquisition succeeded or not.
  #     3. An unlocking callback that signals the end of the critical section.
  #        This will be null if the lock was not acquired successfully.
  #        Optionally, you can pass a callback parameter when invoking the
  #        unlock callback to handle any Redis errors involved in the actual
  #        unlock. This final callback takes two parameters, an error and a
  #        true/false value, indicating whether the lock was actually removed
  #        from Redis. A false value implies that the lock had expired.
  (key, args...) ->
    switch args.length
      when 1
        lockOpts = config
        callback = args[0]
      when 2
        lockOpts = _.extend({}, config, args[0])
        callback = args[1]
      else
        throw 'Invalid number of arguments to lock function'

    retries = 0
    lockValue = uuid.v1()

    setnx_pexpire_args =
      keys: key
      args: [ lockValue, lockOpts.lifetime ]
    delequal_args =
      keys: key
      args: lockValue

    shavaluator = new Shavaluator()
    shavaluator.load luaCommands
    shavaluator.redis = lockOpts.redis

    attemptAcquire = () ->
      # Attempt to acquire a lock with the configured expiration time.
      # Using setnx_pexpire, we'll set a key with a unique value and a TTL.
      #
      # Redis will use the TTL to expire the key, with no further interaction
      # from the lock client.
      #
      # The lock client can release the lock explicitly when its critical
      # section is complete. The delequal command is used to ensure that this
      # client can only delete the lock key if its value is equal to the unique
      # value assigned to the lock when it was first acquired.
      shavaluator.setnx_pexpire setnx_pexpire_args, (err, result) ->
        if err
          # I. Redis error
          callback err, retries
        else if result == 0
          # II. The lock exists and has not yet expired. Attempt to retry.
          if retries >= lockOpts.maxRetries
            callback(new Error('Exceeded max retry count'), retries)
          else
            retries += 1
            setTimeout attemptAcquire, lockOpts.retryTimeout
        else
          # III. Lock acquired! Proceed with the critical section.
          callback null, retries, (unlockCallback) ->
            # To unlock, run an atomic check + delete. Only delete the lock key
            # if the stored value is equal to this lock's expiration time.
            shavaluator.delequal delequal_args, (err, result) ->
              unlockCallback(err, result == 1) if unlockCallback

    # Attempt to acquire the lock for the first time.
    attemptAcquire()
