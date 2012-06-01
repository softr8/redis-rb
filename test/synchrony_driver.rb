# encoding: UTF-8

require 'em-synchrony'

require 'tr8dis'
require 'tr8dis/connection/synchrony'

require File.expand_path("./helper", File.dirname(__FILE__))

#
# if running under Eventmachine + Synchrony (Ruby 1.9+), then
# we can simulate the blocking API while performing the network
# IO via the EM reactor.
#

EM.synchrony do
  r = Tr8dis.new
  r.flushdb

  r.rpush "foo", "s1"
  r.rpush "foo", "s2"

  assert_equal 2, r.llen("foo")
  assert_equal "s2", r.rpop("foo")

  r.set("foo", "bar")

  assert_equal "bar", r.getset("foo", "baz")
  assert_equal "baz", r.get("foo")

  r.set("foo", "a")

  assert_equal 1, r.getbit("foo", 1)
  assert_equal 1, r.getbit("foo", 2)
  assert_equal 0, r.getbit("foo", 3)
  assert_equal 0, r.getbit("foo", 4)
  assert_equal 0, r.getbit("foo", 5)
  assert_equal 0, r.getbit("foo", 6)
  assert_equal 1, r.getbit("foo", 7)

  r.flushdb

  # command pipelining
  r.pipelined do
    r.lpush "foo", "s1"
    r.lpush "foo", "s2"
  end

  assert_equal 2, r.llen("foo")
  assert_equal "s2", r.lpop("foo")
  assert_equal "s1", r.lpop("foo")

  assert_equal "OK", r.client.call(:quit)
  assert_equal "PONG", r.ping

  EM.stop
end
