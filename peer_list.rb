class PeerList
  extend Forwardable

  def initialize(peers = [])
    @peers = peers
  end
  def_delegators :@peers, :<<, :delete

  def contain?(peer_info)
    @peers.any? { |peer| peer_info == [peer.ip, peer.port] }
  end

  def unchoking_remote_peers
    u = @peers.find_all(&:peer_unchoking?)
    self.class.new(u)
  end

  def unchoking_peers
    u = @peers.find_all(&:unchoking?)
    self.class.new(u)
  end

  def interested_remote_peers
    i = @peers.find_all(&:peer_interested?)
    self.class.new(i)
  end

  def interested_peers
    i = @peers.find_all(&:interested?)
    self.class.new(i)
  end

  def all
    @peers
  end
end
