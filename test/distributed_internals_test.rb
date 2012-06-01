# encoding: UTF-8

require "helper"

class TestDistributedInternals < Test::Unit::TestCase

  include Helper::Distributed

  def test_provides_a_meaningful_inspect
    nodes = ["redis://localhost:#{PORT}/15", *NODES]
    redis = Tr8dis::Distributed.new nodes

    assert_equal "#<Tr8dis client v#{Tr8dis::VERSION} for #{redis.nodes.map(&:id).join(', ')}>", redis.inspect
  end
end
