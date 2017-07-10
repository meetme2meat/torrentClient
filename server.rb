require 'utils'
class Server < EM::Connection
  extend Utils
  def self.run(client)
    puts host
    puts port
    EM.start_server host, port, self, client: client
  end

  attr_reader :client
  def initialize(args)
    @client = args[:client]
  end

  def post_init
    p "-- Initiated connection -- #{client.id}"
  end

  def receive_data(data)
     puts data
  end
end
