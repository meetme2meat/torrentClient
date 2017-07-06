class SignalHandler
  def self.trap!
    Signal.trap('USR1') do
      $debug = !$debug
      puts "Debug now: #{$debug}"
    end

    Signal.trap('TERM') do
      puts 'Stopping ...'
      EM.stop
    end

    Signal.trap('INT') do
      puts 'Stopping ...'
      EM.stop
    end
  end
end
