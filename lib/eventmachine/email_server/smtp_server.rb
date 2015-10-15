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
      @@classifier = nil
      
      def self.reset
        @@graylist = nil
        @@dnsbl_check = nil
        @@ratelimiter = nil
        @@reverse_ptr_check = false
        @@spf_check = false
        @@reject_filters = Array.new
        @@classifier = nil
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
      
      def self.classifier(classifier=nil)
        if not classifier.nil?
          @@classifier = classifier
        end
        @@classifier
      end

      attr_accessor :debug
      
      def initialize(hostname, userstore, emailstore)
        @hostname = hostname
        @userstore = userstore
        @emailstore = emailstore
        @debug = false
        @data_mode = false
        @email_body = ""
        @ptr_ok = true
        @dnsbl_ok = true
        @rate_ok = true
        @gray_ok = true
        @spf_ok = true
        @reject_ok = true
        @classifier_ok = true
        @pending_checks = [:content]
      end
      
      def post_init
        send "220 #{@hostname} ESMTP Service ready"
      end
      
			def receive_data(data)
        puts ">> #{data}" if @debug
        data.split(/\n/).each do |line|
          process_line(line+"\n")
        end
      end
      
      def check_ptr(helo, ip)
        if helo =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ and helo == ip
          @ptr_ok = true
        elsif @@reverse_ptr_check
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
      
      def check_classifier
        if @@classifier
          if @@classifier.block?(@email_body)
            @classifier_ok = false
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
              if helo =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ and helo == ip
                helo = nil
              end
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
        if @debug
          puts "ptr_ok        = #{@ptr_ok}"
          puts "rate_ok       = #{@rate_ok}"
          puts "gray_ok       = #{@gray_ok}"
          puts "reject_ok     = #{@reject_ok}"
          puts "dnsbl_ok      = #{@dnsbl_ok}"
          puts "spf_ok        = #{@spf_ok}"
          puts "classifier_ok = #{@classifier_ok}"
        end
        if @ptr_ok and @rate_ok and @gray_ok and @reject_ok and @dnsbl_ok and @spf_ok and @classifier_ok
          ans = "250 OK"
          save
        else
          ans = "451 Requested action aborted: local error in processing"
        end
        send(ans)
      end
      
      def send(msg)
        puts "<< #{msg}" if @debug
        send_data("#{msg}\r\n")
      end
      
     	def process_line(line)
    		if (@data_mode) && (line.chomp == '.')
    			@data_mode = false
          check_reject
          check_classifier
          @pending_checks -= [:content]
          p @pending_checks if @debug
          if @pending_checks.length == 0
            send_answer
          end
    		elsif @data_mode
    			@email_body += line
    		elsif (line =~ /^(HELO|EHLO) (.*)/)
          helo = $2.chomp.gsub(/^\[/,'').gsub(/\]$/,'')
          port, ip = Socket.unpack_sockaddr_in(get_peername)
          check_ptr(helo, ip)
          check_dnsbl(ip)
          check_gray(ip)
          check_ratelimit(ip)
          send("250 hello #{ip} (#{helo})")
    		elsif (line =~ /^QUIT/)
          send("221 #{@hostname} ESMTP server closing connection")
          self.close_connection
    		elsif (line =~ /^MAIL FROM\:/)
    			@mail_from = (/^MAIL FROM\:\s*<(.+)>.*$/).match(line)[1]
          if @@spf_check
            port, ip = Socket.unpack_sockaddr_in(get_peername)
            check_spf(helo, ip, @mail_from)
          end
          send("250 OK")
    		elsif (line =~ /^RCPT TO\:/)
    			rcpt_to = (/^RCPT TO\:\s*<(.+)>.*$/).match(line)[1]
    			if @userstore.user_by_emailaddress(rcpt_to.strip)
    				@rcpt_to = rcpt_to
            send("250 OK")
          else
            send("550 No such user here")
          end
    		elsif (line =~ /^DATA/)
    			if @rcpt_to
    				@data_mode = true
    				@email_body = ''
    				send("354 Enter message, ending with \".\" on a line by itself")
          else
            send("500 ERROR")
          end
    		else
    			send("500 ERROR")
    		end
    	end
      
    	def save
    		begin
    			subject = @email_body.match(/Subject\:\s*(.*?)[\r\n]/i)[1]
    			u = @userstore.user_by_emailaddress(@rcpt_to.strip)
    		rescue Exception => err
    			puts err if @debug
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