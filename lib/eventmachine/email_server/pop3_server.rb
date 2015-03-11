require 'eventmachine'
require 'digest/md5'

module EventMachine
	module EmailServer
		class POP3Server < EventMachine::Connection
      @@capabilities = [ "TOP", "USER", "UIDL" ]
      def initialize(hostname, userstore, emailstore)
        @hostname = hostname
        @userstore = userstore
        @emailstore = emailstore
        @state = 'auth' # 'trans' and 'data'
        @auth_attempts = 0
        @apop_challenge = "<#{rand(10**4 - 1)}.#{rand(10**9 - 1)}@#{@hostname}>"
        @debug = true
        @emails = Array.new
      end
      
      def post_init
        puts ">> +OK POP3 server ready #{@apop_challenge}" if @debug
        send_data("+OK POP3 server ready #{@apop_challenge}\r\n")
      end
      
			def receive_data(data)
        puts ">> #{data}" if @debug
        data.split(/[\r\n]+/).each do |line|
          process_line(line)
        end
      end
      
      def send(data, close=false)
        puts "<< #{data}" if @debug
        send_data("#{data}\r\n")
        close_connection if close
      end
      
      def unbind(reason=nil)
        @emails.find_all {|e| e.marked}.each do |email|
          @emailstore.delete_email(email)
          puts "deleted #{email.id}" if @debug
        end
      end
      
    	def process_line(line)
    		case @state
    		when 'auth'
          auth_state(line)
    		when 'trans'
          trans_state(line)
    		when 'update'
          update_state(line)
        else
      		send("-ERR unknown command")
    		end
    	end
      
      def auth_state(line)
  			case line
  			when /^QUIT$/
  				send("+OK dewey POP3 server signing off", true)
        when /^CAPA$/
          send("+OK Capability list follows\r\n"+@@capabilities.join("\r\n")+"\r\n.")
  			when /^USER (.+)$/
  				user($1)
  				if @user
  					send("+OK #{@user.username} is most welcome here")
  				else
  					@failed += 1
  					if @failed > 2
  						send("-ERR you're out!", true)
            else
    					send("-ERR sorry, no mailbox for #{$1} here")
  					end
  				end
  			when /^PASS (.+)$/
  				if pass($1)
  					@state = 'trans'
  					emails
  					msgs, bytes = stat
  					send("+OK #{@user.username}'s maildrop has #{msgs} messages (#{bytes} octets)")
  				else
  					@failed += 1
  					if @failed > 2
  						send("-ERR you're out!", true)
            else
              send("-ERR no dope.")
            end
  				end
  			when /^APOP ([^\s]+) (.+)$/
  				if apop($1,$2)
  					@state = 'trans'
  					emails
  					send("+OK #{@user.username} is most welcome here")
  				else
  					@failed += 1
  					if @failed > 2
  						send("-ERR you're out!", true)
            else
  					  send("-ERR sorry, no mailbox for #{$1} here")
            end
  				end
        else
          send("-ERR unknown command")
  			end
      end
      
      def trans_state(line)
  			case line
  			when /^NOOP$/
  				send("+OK")
  			when /^STAT$/
  				msgs, bytes = stat
  				send("+OK #{msgs} #{bytes}")
  			when /^LIST$/
  				msgs, bytes = stat
  				msg = "+OK #{msgs} messages (#{bytes} octets)\r\n"
  				list.each do |num, bytes|
  					msg += "#{num} #{bytes}\r\n"
  				end
  				msg += "."
  				send(msg)
  			when /^LIST (\d+)$/
  				msgs, bytes = stat
  				num, bytes = list($1)
  				if num
  					send("+OK #{num} #{bytes}")
  				else
  					send("-ERR no such message, only #{msgs} messages in maildrop")
  				end
  			when /^RETR (\d+)$/
  				msg = retr($1)
  				if msg
  					msg = "+OK #{msg.length} octets\r\n" + msg + "\r\n."
  				else
  					msg = "-ERR no such message"
  				end
  				send(msg)
  			when /^DELE (\d+)$/
  				if dele($1)
  					send("+OK message #{$1} marked")
  				else
  					send("-ERR message #{$1} already marked")
  				end
  			when /^RSET$/
  				rset
  				msgs, bytes = stat
  				send("+OK maildrop has #{msgs} messages (#{bytes} octets)")
  			when /^QUIT$/
  				@state = 'update'
  				quit
  				msgs, bytes = stat
  				if msgs > 0
  					send("+OK dewey POP3 server signing off (#{msgs} messages left)", true)
  				else
  					send("+OK dewey POP3 server signing off (maildrop empty)", true)
  				end
  			when /^TOP (\d+) (\d+)$/
  				lines = $2
  				msg = retr($1)
  				unless msg
  					send("-ERR no such message")
          else
    				cnt = nil
    				final = ""
    				msg.split(/\n/).each do |l|
    					final += l+"\n"
    					if cnt
    						cnt += 1
    						break if cnt > lines
    					end
    					if l !~ /\w/
    						cnt = 0
    					end
    				end
    				send("+OK\r\n"+final+"\r\n.")
          end
  			when /^UIDL$/
  				msgid = 0
  				msg = ''
  				@emails.each do |e|
  					msgid += 1
  					next if e.marked
  					msg += "#{msgid} #{Digest::MD5.new.update(e.body).hexdigest}\r\n"
  				end
  				send("+OK\r\n#{msg}.")
        else
          send("-ERR unknown command")
  			end
      end
      
      def update_state(line)
  			case line
  			when /^QUIT$/
  				send("+OK dewey POP3 server signing off", true)
        else
          send("-ERR unknown command")
  			end
      end
      
    	def user(username)
    		@user = @userstore.user_by_username(username)
    	end
      
    	def pass(password)
    		return false unless @user
    		return false unless @user.password == password
    		true
    	end
      
    	def emails
        @emails = @emailstore.emails_by_userid(@user.id)
    	end
      
    	def stat
    		msgs = bytes = 0
    		@emails.each do |e|
    			next if e.marked == 'true'
    			msgs += 1
    			bytes += e.body.length
    		end
    		[msgs, bytes]
    	end
      
    	def list(msgid = nil)
    		msgid = msgid.to_i if msgid
    		if msgid
    			return false if msgid > @emails.length or @emails[msgid-1].marked
    			return [ [msgid, @emails[msgid].body.length] ]
    		else
    			msgs = []
    			@emails.each_with_index do |e,i|
    				msgs << [ i + 1, e.body.length ]
    			end
    			msgs
    		end
    	end
      
    	def retr(msgid)
    		msgid = msgid.to_i
    		return false if msgid > @emails.length or @emails[msgid-1].marked == 'true'
    		@emails[msgid-1].body
    	end
      
    	def dele(msgid)
    		msgid = msgid.to_i
    		return false if msgid > @emails.length
    		@emails[msgid-1].marked = true
    	end
      
    	def rset
    		@emails.each do |e|
    			e.marked = false
    		end
    	end
      
    	def quit
        @emails.find_all {|e| e.marked}.each do |email|
          @emailstore.delete_email(email)
        end
    	end
      
    	def apop(username, hash)
    		user(username)
    		return false unless @user
    		if Digest::MD5.new.update("#{@apop_challenge}#{@user.password}").hexdigest == hash
    			return true
    		end
    		false
    	end

    end
  end
end
      
