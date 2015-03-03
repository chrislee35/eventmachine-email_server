module EventMachine
  module DNS
    class Resolver
      def self.resolve(hostname, qclass=Resolv::DNS::Resource::IN::A)
        Request.new(socket, hostname, qclass)
      end
    end
    class Request
      def initialize(socket, hostname, qclass)
        @socket = socket
        @hostname = hostname
        @qclass = qclass
        @tries = 0
        @last_send = Time.at(0)
        @retry_interval = 3
        @max_tries = 5
        if addrs = Resolver.hosts[hostname]
          succeed addrs
        else
          EM.next_tick { tick }
        end
      end
      
      def receive_answer(msg)
        addrs = []
        msg.each_answer do |name,ttl,data|
          if data.respond_to? :address
            addrs << data.address.to_s
          elsif data.respond_to? :name
            addrs << data.name.to_s
          elsif data.respond_to? :strings
            addrs << data.strings.join("\n")
          else
            addrs << data.to_s
          end
        end
        if addrs.empty?
          fail "rcode=#{msg.rcode}"
        else
          succeed addrs
        end
      end      
      
      private

      def packet
        msg = Resolv::DNS::Message.new
        msg.id = id
        msg.rd = 1
        msg.add_question @hostname, @qclass
        msg
      end
    end
  end
end
