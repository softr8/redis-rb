# encoding: UTF-8

require "helper"

class TestInternals < Test::Unit::TestCase

  include Helper::Client

  def test_logger
    r.ping

    assert log.string =~ /Tr8dis >> PING/
      assert log.string =~ /Tr8dis >> \d+\.\d+ms/
  end

  def test_logger_with_pipelining
    r.pipelined do
      r.set "foo", "bar"
      r.get "foo"
    end

    assert log.string["SET foo bar"]
    assert log.string["GET foo"]
  end

  def test_recovers_from_failed_commands
    # See https://github.com/redis/redis-rb/issues#issue/28

    assert_raise(Tr8dis::CommandError) do
      r.command_that_doesnt_exist
    end

    assert_nothing_raised do
      r.info
    end
  end

  def test_raises_on_protocol_errors
    redis_mock(:ping => lambda { |*_| "foo" }) do |redis|
      assert_raise(Tr8dis::ProtocolError) do
        redis.ping
      end
    end
  end

  def test_provides_a_meaningful_inspect
    assert_equal "#<Redis client v#{Tr8dis::VERSION} for redis://127.0.0.1:#{PORT}/15>", r.inspect
  end

  def test_redis_current
    assert_equal "127.0.0.1", Tr8dis.current.client.host
    assert_equal 6379, Tr8dis.current.client.port
    assert_equal 0, Tr8dis.current.client.db

    Tr8dis.current = Tr8dis.new(OPTIONS.merge(:port => 6380, :db => 1))

    t = Thread.new do
      assert_equal "127.0.0.1", Tr8dis.current.client.host
      assert_equal 6380, Tr8dis.current.client.port
      assert_equal 1, Tr8dis.current.client.db
    end

    t.join

    assert_equal "127.0.0.1", Tr8dis.current.client.host
    assert_equal 6380, Tr8dis.current.client.port
    assert_equal 1, Tr8dis.current.client.db
  end

  def test_default_id_with_host_and_port
    redis = Tr8dis.new(OPTIONS.merge(:host => "host", :port => "1234", :db => 0))
    assert_equal "redis://host:1234/0", redis.client.id
  end

  def test_default_id_with_host_and_port_and_explicit_scheme
    redis = Tr8dis.new(OPTIONS.merge(:host => "host", :port => "1234", :db => 0, :scheme => "foo"))
    assert_equal "redis://host:1234/0", redis.client.id
  end

  def test_default_id_with_path
    redis = Tr8dis.new(OPTIONS.merge(:path => "/tmp/redis.sock", :db => 0))
    assert_equal "redis:///tmp/redis.sock/0", redis.client.id
  end

  def test_default_id_with_path_and_explicit_scheme
    redis = Tr8dis.new(OPTIONS.merge(:path => "/tmp/redis.sock", :db => 0, :scheme => "foo"))
    assert_equal "redis:///tmp/redis.sock/0", redis.client.id
  end

  def test_override_id
    redis = Tr8dis.new(OPTIONS.merge(:id => "test"))
    assert_equal redis.client.id, "test"
  end

  def test_timeout
    assert_nothing_raised do
      Tr8dis.new(OPTIONS.merge(:timeout => 0))
    end
  end

  def test_time
    return if version < "2.5.4"

    # Test that the difference between the time that Ruby reports and the time
    # that Tr8dis reports is minimal (prevents the test from being racy).
    rv = r.time

    redis_usec = rv[0] * 1_000_000 + rv[1]
    ruby_usec = Integer(Time.now.to_f * 1_000_000)

    assert 500_000 > (ruby_usec - redis_usec).abs
  end

  def test_connection_timeout
    assert_raise Tr8dis::CannotConnectError do
      Tr8dis.new(OPTIONS.merge(:host => "10.255.255.254", :timeout => 0.1)).ping
    end
  end

  def close_on_ping(seq)
    $request = 0

    command = lambda do
      idx = $request
      $request += 1

      rv = "+%d" % idx
      rv = nil if seq.include?(idx)
      rv
    end

    redis_mock(:ping => command, :timeout => 0.1) do |redis|
      yield(redis)
    end
  end

  def test_retry_by_default
    close_on_ping([0]) do |redis|
      assert_equal "1", redis.ping
    end
  end

  def test_retry_when_wrapped_in_with_reconnect_true
    close_on_ping([0]) do |redis|
      redis.with_reconnect(true) do
        assert_equal "1", redis.ping
      end
    end
  end

  def test_dont_retry_when_wrapped_in_with_reconnect_false
    close_on_ping([0]) do |redis|
      assert_raise Tr8dis::ConnectionError do
        redis.with_reconnect(false) do
          redis.ping
        end
      end
    end
  end

  def test_dont_retry_when_wrapped_in_without_reconnect
    close_on_ping([0]) do |redis|
      assert_raise Tr8dis::ConnectionError do
        redis.without_reconnect do
          redis.ping
        end
      end
    end
  end

  def test_retry_only_once_when_read_raises_econnreset
    close_on_ping([0, 1]) do |redis|
      assert_raise Tr8dis::ConnectionError do
        redis.ping
      end

      assert !redis.client.connected?
    end
  end

  def test_don_t_retry_when_second_read_in_pipeline_raises_econnreset
    close_on_ping([1]) do |redis|
      assert_raise Tr8dis::ConnectionError do
        redis.pipelined do
          redis.ping
          redis.ping # Second #read times out
        end
      end

      assert !redis.client.connected?
    end
  end

  def test_connecting_to_unix_domain_socket
    assert_nothing_raised do
      Tr8dis.new(OPTIONS.merge(:path => "/tmp/redis.sock")).ping
    end
  end

  driver(:ruby, :hiredis) do
    def test_bubble_timeout_without_retrying
      serv = TCPServer.new(6380)

      redis = Tr8dis.new(:port => 6380, :timeout => 0.1)

      assert_raise(Tr8dis::TimeoutError) do
        redis.ping
      end

    ensure
      serv.close if serv
    end
  end
end
