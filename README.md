# redis-exp-lock-js

Uses Redis to provide a mechanism for distributed mutual exclusion. If you want
to prevent multiple nodes on a network from accessing a resource at the same
time, this is for you. This lock implementation uses a finite but configurable
expiration time.

Unlike most `SETNX`-based solutions, this uses Redis's Lua functionality. The
result is cleaner code and fewer race conditions. Lock expiration is handled by
the Redis server itself, using the `EXPIRE` command, thus eliminating the need
for precise time synchronization between your application hosts.

## Example

```js
redis = require('redis');
redisExpLock = require('redis-exp-lock');

// Configure a lock function
withLock = redisExpLock({redis: redis.createClient()});

// Use the lock function to provide mutual exclusion.
withLock(function(err, critSecDone) {
  if (err) throw err;
  doStuffThatShouldNotBeInterrupted();
  critSecDone();
});
```

## How to use the library

### Installation

    npm install redis-exp-lock

### Setup

Requiring the module will result in a **lock configuration function**.

```js
redisExpLock = require('redis-exp-lock')
```

Calling the lock configuration function yields a **lock function** that will peform the actual locking. The lock configuration function takes one optional configuration argument, an object with any of the following fields:

##### redis

The Redis client.

##### lifetime

The lifetime of the lock, in milliseconds. A lock's lifetime begins counting down as soon as the Redis server receives an `EXPIRE` command from the lock function. Defaults to 1000 milliseconds (one second).

##### maxRetries

In the event that the lock has been acquired by another process, the lock function can automatically attempt to re-acquire the lock, up to a configurable number of attempts. Defaults to zero (no automatic retries).

##### retryTimeout

The amount of time the lock function will wait before attempting to re-acquire the lock. Defaults to five milliseconds.

### Acquiring and releasing the lock

The lock function takes two or three arguments:

* A **Redis key** where the lock will be stored. This is most likely the name of the resource you are trying to lock.
* An optional **settings object**, with overrides to the original lock configuration.
* A **callback** that takes two arguments:
    * An **error** object. This is null if the lock attempt was successful.
    * A **release function**, to be called in your application code after the critical section has completed. This will cause the lock to be released. Since the release function is itself asynchronous, you can pass it a callback that will be invoked when the release has been confirmed.

```js
withLock = redisExpLock({redis: redis.createClient(), maxRetries: 2});

withLock('bankAccount', function(err, critSecDone) {
  if (err) return;
  bankAccount.addMoney(100000);

  critSecDone(function(err) {
    if (err) return;
    console.log("Lock successfully released!");
  });
});
```

## Algorithm

#### Lock acquisition

Locks are acquired by setting a Redis key with a UUID generated immediately prior to the lock attempt. A Lua script provides the following atomic sequence:

1. Use `SETNX` to set the value of the given key to the UUID.
2. If `SETNX` was successful, use `PEXPIRE` to set a lifetime on the key, managed by Redis.

Since the Redis server manages the lifetime, there is no need for any client-side logic for managing lock expiration, and thus no need to ensure that clients are time-synchronized.

#### Lock release

Locks are released by deleting the Redis key, **if and only if** the key's value matches the UUID generated during a successful lock attempt. A Lua script provides the following atomic sequence:

1. `GET` the value of the key.
2. If the value of the key is the same as the UUID, then use `DEL` to remove the key.

Without using a Lua script to ensure atomicity, it's possible to encounter subtle race conditions, in which another client acquires the lock between the two steps above.