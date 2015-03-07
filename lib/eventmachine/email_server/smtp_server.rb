require 'eventmachine'
require 'eventmachine/dnsbl'
require 'spf'

module EventMachine
	module EmailServer
		class SMTPServer < EventMachine::Connection
      @@graylist = nil
      @@dnsbl_check = nil
      @@ratelimiter = nil
      @@reverse_ptr_check = false
      @@spf_check = false
      @@reject_filters = Array.new
      
      def self.reset
        @@graylist = nil
        @@dnsbl_check = nil
        @@ratelimiter = nil
        @@reverse_ptr_check = false
        @@spf_check = false
        @@reject_filters = Array.new
      end
      
      def self.reverse_ptr_check(ptr=nil)
        if not ptr.nil?
          @@reverse_ptr_check = ptr
        end
        @@reverse_ptr_check
      end
      
      def self.graylist(graylist=nil)
        if graylist
          @@graylist = graylist
        end
        @@graylist
      end
      
      def self.dnsbl_check(dnsbl_check=nil)
        if not dnsbl_check.nil?
          @@dnsbl_check = dnsbl_check
        end
        @@dnsbl_check
      end
      
      def self.ratelimiter(ratelimiter=nil)
        if ratelimiter
          @@ratelimiter = ratelimiter
        end
        @@ratelimiter
      end
      
      def self.reject_filters(filters=nil)
        if filters
          @@reject_filters = filters
        end
        @@reject_filters
      end
      
      def self.spf_check(spf=nil)
        if not spf.nil?
          @@spf_check = spf
        end
        @@spf_check
      end 

      def initialize(hostname, userstore, emailstore)
        @hostname = hostname
        @userstore = userstore
        @emailstore = emailstore
        @debug = true
        @data_mode = false
        @email_body = ""
        @ptr_ok = true
        @dnsbl_ok = true
        @rate_ok = true
        @gray_ok = true
        @reject_ok = true
        @pending_checks = Array.new
      end
      
      def post_init
        puts ">> 220 hello" if @debug
        send_data "220 #{@hostname} ESMTP Service ready\n"
      end
      
			def receive_data(data)
        puts ">> #{data}" if @debug
        data.split(/\n/).each do |line|
          ok, op = process_line(line+"\n")
          if op
            puts "<< #{op}" if @debug
            send_data(op+"\r\n")
          end
        end
      end
      
      def check_ptr(helo, ip)
        if @@reverse_ptr_check
          @ptr_ok = false
          @pending_checks << :ptr
          d = EM::DNS::Resolver.resolve helo
          d.callback { |r|
            @ptr_ok = r.include?(ip)
            @pending_checks -= [:ptr]
            if @pending_checks.length == 0
              send_answer
            end
          }
        end
      end
      
      def check_dnsbl(ip)
        if @@dnsbl_check
          @dnsbl_ok = false
          @pending_checks << :dnsbl
          EventMachine::DNSBL::Client.check(ip) do |results|
            @dnsbl_ok = ! EventMachine::DNSBL::Client.blacklisted?(results)
            @pending_checks -= [:dnsbl]
            if @pending_checks.length == 0
              send_answer
            end
          end
        end
      end
      
      def check_ratelimit(ip)
        if @@ratelimiter
          @rate_ok = @@ratelimiter.use(ip)
        end
      end
      
      def check_gray(ip)
        if @@graylist
          @gray_ok = @@graylist.has_key?(ip)
          @@graylist[ip] = true
        end
      end
      
      def check_reject
        @@reject_filters.each do |filter|
          if filter.match(@email_body)
            @reject_ok = false
            return
          end
        end
      end
      
      def check_spf(helo, client_ip, identity)
        if @@spf_check
          @spf_ok = false
          @pending_checks << :spf
          
          spf_dispatcher = EventMachine::ThreadedResource.new do
            spf_server = SPF::Server.new
          end

          pool = EM::Pool.new

          pool.add spf_dispatcher

          pool.perform do |dispatcher|
            completion = dispatcher.dispatch do |spf_server|

              request = SPF::Request.new(
                versions:      [1, 2],             # optional
                scope:         'mfrom',            # or 'helo', 'pra'
                identity:      identity,
                ip_address:    client_ip,
                helo_identity: helo   # optional
              )

              result = spf_server.process(request)
            end
  
            completion.callback do |result|
              if result.code == :pass
                @spf_ok = true
              elsif result.code == :fail
                @spf_ok = false
              elsif result.code == :softfail
                @spf_ok = true
              elsif result.code == :neutral
                @spf_ok = true
              else
                @spf_ok = false
              end
              @pending_checks -= [:spf]
              if @pending_checks.length == 0
                send_answer
              end
            end
  
            completion
          end          
        end
      end
      
      def send_answer
        if @ptr_ok and @rate_ok and @gray_ok and @reject_ok and @dnsbl_ok and @spf_ok
          ans = "250 OK"
        else
          ans = "451 Requested action aborted: local error in processing"
        end
        puts "<< #{ans}" if @debug
        send_data(ans+"\r\n")
      end
      
     	def process_line(line)
    		if (@data_mode) && (line.chomp =~ /^\.$/)
    			@data_mode = false
          check_reject
          if @pending_checks.length == 0
            send_answer
          end
          return true, nil
    		elsif @data_mode
    			@email_body += line
    			return true, nil
    		elsif (line =~ /^(HELO|EHLO) (.*)/)
          helo = $2.chomp
          port, ip = Socket.unpack_sockaddr_in(get_peername)
          check_ptr(helo, ip)
          check_dnsbl(ip)
          check_gray(ip)
          check_ratelimit(ip)
    			return true, "250 hello #{ip} (#{helo})"
    		elsif (line =~ /^QUIT/)
    			return false, "221 bye bye"
    		elsif (line =~ /^MAIL FROM\:/)
    			@mail_from = (/^MAIL FROM\:<(.+)>.*$/).match(line)[1]
          if @@spf_check
            port, ip = Socket.unpack_sockaddr_in(get_peername)
            check_spf(helo, ip, @mail_from)
          end
    			return true, "250 OK"
    		elsif (line =~ /^RCPT TO\:/)
    			rcpt_to = (/^RCPT TO\:<(.+)>.*$/).match(line)[1]
    			if @userstore.user_by_emailaddress(rcpt_to.strip)
    				@rcpt_to = rcpt_to
    				return true, "250 OK"
    			end
    			return false, "550 No such user here"
    		elsif (line =~ /^DATA/)
    			if @rcpt_to
    				@data_mode = true
    				@email_body = ''
    				return true, "354 Enter message, ending with \".\" on a line by itself"
    			end
    			return true, "500 ERROR"
    		else
    			return true, "500 ERROR"
    		end
    	end
      
    	def save
    		begin
    			subject = @email_body.match(/Subject\: (.*?)[\r\n]/i)[1]
    			u = @userstore.user_by_emailaddress(@rcpt_to.strip)
    		rescue Exception => err
    			puts err
    			return
    		end
    		if u and @mail_from and @rcpt_to
    			subject ||= ''
          @emailstore << Email.new(nil, @mail_from, @rcpt_to, subject, @email_body, u.id)
    		end
    	end
    end
  end
end