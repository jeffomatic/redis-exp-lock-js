module.exports =
  # Like SETNX, but also issues an expire if the value is set. Returns the
  # result of SETNX.
  setnx_pexpire:
    """
    local result = redis.call('SETNX', KEYS[1], ARGV[1])
    if result == 1 then
      redis.call('PEXPIRE', KEYS[1], ARGV[2])
    end
    return result
    """

  # Deletes keys if they equal the given values
  delequal:
    """
    local deleted = 0
    if redis.call('GET', KEYS[1]) == ARGV[1] then
      return redis.call('DEL', KEYS[1])
    end
    return 0
    """