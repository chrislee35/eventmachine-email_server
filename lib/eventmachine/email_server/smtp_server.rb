require 'eventmachine'

module EventMachine
	module EmailServer
		class SMTPServer < EventMachine::Connection
      @@graylist = nil
      @@dnsbl_client = nil
      @@ratelimiter = nil
      @@reverse_ptr_check = true
      @@spf_check = false
      @@reject_filters = Array.new
      
      def self.graylist(graylist=nil)
        if graylist
          @@graylist = graylist
        end
        @@graylist
      end
      
      def self.dnsbl(dnsbl_client=nil)
        if dnsbl_client
          @@dnsbl_client = dnsbl_client
        end
        @@dnsbl_client
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
      
      def self.spf(spf=nil)
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
          d = EM::DNS::Resolver.resolve helo
          d.callback { |r|
            @ptr_ok = r.include?(ip)
          }
        end
      end
      
      def check_dnsbl(ip)
        if @@dnsbl_client
          # this needs to be changed into a EM component with a callback
          res = @@dnsbl_client.lookup(ip)
          @dnsbl_ok = (res.length == 0)
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
      
      def check_spf(ip, domain)
        if @@spf_check
          @spf_ok = false
          d = EM::DNS::Resolver.resolve helo
          d.callback { |r|
            @ptr_ok = r.include?(ip)
          }
        end
      end
      
     	def process_line(line)
    		if (@data_mode) && (line.chomp =~ /^\.$/)
    			@data_mode = false
          check_reject
          if @ptr_ok and @dnsbl_ok and @rate_ok and @gray_ok and @reject_ok
            save
          else
            return true, "451	Requested action aborted: local error in processing"
          end
    			return true, "250 OK"
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