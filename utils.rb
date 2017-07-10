require 'socket'
module Utils
  def host
    Socket.ip_address_list.detect(&:ipv4_private?).ip_address
  end

  def port
    6881
  end
end
