unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

require_relative 'helper'
include EventMachine::EmailServer
require 'net/pop'
require 'net/smtp'
require 'ratelimit/bucketbased'

module EventMachine
  module DNS
    class Socket < EventMachine::Connection    
      def send_packet(pkt)
        send_datagram(pkt, nameserver, 53)
      end
    end
  end
end

class TestEmailServer < Minitest::Test
  def setup
    @test_vector = Proc.new { |test_name|
      (test_name.to_s =~ /test/)
    }
    if File.exist?("test/test.sqlite3")
      File.unlink("test/test.sqlite3")
    end
    if File.exist?("email_server.sqlite3")
      File.unlink("email_server.sqlite3")
    end
  end
  
  def teardown
    if File.exist?("test/test.sqlite3")
      File.unlink("test/test.sqlite3")
    end
    if File.exist?("email_server.sqlite3")
      File.unlink("email_server.sqlite3")
    end
  end
  
  def setup_user(userstore)
    userstore << User.new(1, "chris", "chris", "chris@example.org")
  end
  
  def start_servers(userstore, emailstore)
    pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
    smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
  end  
  
  def send_email(expected_status="250")
    from = "friend@example.org"
    to = "chris@example.org"
    msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
    Thread.new do
      smtp = Net::SMTP.start('localhost', 2025)
      ret = smtp.send_message msg, from, to
      assert_equal(expected_status, ret.status)
    end
  end
  
  def pop_some_email
    Thread.new do 
      pop = Net::POP3.APOP(true).new('localhost',2110)
      pop.start("chris","chris")
      refute(pop.mails.empty?)
      pop.each_mail do |m|
        assert_equal("From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
", m.mail)
        m.delete
      end
    end
  end    

  def pop_no_email
    Thread.new do 
      pop = Net::POP3.APOP(true).new('localhost',2110)
      pop.start("chris","chris")
      assert(pop.mails.empty?)
    end
  end  

  def run_test(userstore, emailstore)
    EM.run {
      start_servers(userstore, emailstore)
      timer = EventMachine::Timer.new(0.1) do
        send_email
      end
      timer2 = EventMachine::Timer.new(0.2) do
        pop_some_email
      end
      
      timer3 = EventMachine::Timer.new(0.3) do
        pop_no_email
      end
      
      timer4 = EventMachine::Timer.new(0.4) do
        EM.stop
      end
    }  
  end
  
  def test_memory_store
    return unless @test_vector.call(__method__)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)
    run_test(userstore, emailstore)
  end
  
  def test_sqlite3_store
    return unless @test_vector.call(__method__)
    s = SQLite3::Database.new("test/test.sqlite3")
    userstore = Sqlite3UserStore.new(s)
    emailstore = Sqlite3EmailStore.new(s)
    setup_user(userstore)
    run_test(userstore, emailstore)
  end
  
  def test_graylisting
    return unless @test_vector.call(__method__)
    SMTPServer.reset
    SMTPServer.graylist(Hash.new)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      
      timer = EventMachine::Timer.new(0.1) do
        send_email("451")
      end
      timer2 = EventMachine::Timer.new(0.2) do
        send_email
      end
      timer3 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
      
    }
  end
 
  def test_ratelimit
    return unless @test_vector.call(__method__)
    config = {
      'default' => RateLimit::Config.new('default', 2, 2, -2, 1, 1, 1),
    }
    storage = RateLimit::Memory.new
    rl = RateLimit::BucketBased.new(storage, config, 'default')
    SMTPServer.reset
    SMTPServer.ratelimiter(rl)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          2.times do
            send_email
          end
          send_email("451")
        end
      end
      timer2 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
    }
  end
  
  def test_reject_list
    return unless @test_vector.call(__method__)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          send_email
          SMTPServer.reject_filters << /remember/
        end
      end
      timer2 = EventMachine::Timer.new(0.2) do
        send_email("451")
      end
      timer3 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
      
    }
  end
  
  def test_dnsbl
    return unless @test_vector.call(__method__)
    #Monkeypatching for testing
    memzone = EventMachine::DNSBL::Zone::MemoryZone.new
    EM::DNS::Resolver.nameservers = ["127.0.0.1"]
    EventMachine::DNSBL::Client.config({
      "EXAMPLE_DNSBL" => {
        :domain => "example.com",
        :type => :ip,
        "127.0.0.2" => "Blacklisted as an example"
      }
    })
    SMTPServer.reset
    SMTPServer.dnsbl_check(true)
    
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      EM::open_datagram_socket "0.0.0.0", 2053, EventMachine::DNSBL::Server, memzone
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      timer = EventMachine::Timer.new(0.1) do
        send_email
      end
      
      timer2 = EventMachine::Timer.new(1.2) do
        memzone.add_dnsblresource(
          EventMachine::DNSBL::Zone::DNSBLResourceRecord.new(
            "example.com", 
            /\d+\.0\.0\.127$/, 
            300, 
            Resolv::DNS::Resource::IN::A.new("127.0.0.4"),
            Time.now.to_i + 3600
          )
        )
        Thread.new do
          send_email("451")
        end
      end
      
      timer3 = EventMachine::Timer.new(3.0) do
        EM.stop
      end
            
    }
  end
  
  def test_spf
    return unless @test_vector.call(__method__)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)
    
    SMTPServer.reset
    SMTPServer.spf_check(true)
    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      timer = EventMachine::Timer.new(0.1) do
        send_email("451")
      end
      timer2 = EventMachine::Timer.new(1) do
        EM.stop
      end
    }
    
  end
    
  def test_example
    return unless @test_vector.call(__method__)
    #require 'eventmachine/email_server'
    #include EventMachine::EmailServer
    #require 'ratelimit/bucketbased'
    #require 'dnsbl/client'
  
    #require 'sqlite3'
    s = SQLite3::Database.new("email_server.sqlite3")
    userstore = Sqlite3UserStore.new(s)
    emailstore = Sqlite3EmailStore.new(s)
    userstore << User.new(1, "chris", "chris", "chris@example.org")
  
    config = {
      'default' => RateLimit::Config.new('default', 2, 2, -2, 1, 1, 1),
    }
    storage = RateLimit::Memory.new
    rl = RateLimit::BucketBased.new(storage, config, 'default')
  
  
    SMTPServer.reset
    SMTPServer.reverse_ptr_check(true)
    SMTPServer.graylist(Hash.new)
    SMTPServer.ratelimiter(rl)
    SMTPServer.dnsbl_check(true)  
    SMTPServer.reject_filters << /viagra/i
  
    EM.run {
      pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      timer = EventMachine::Timer.new(0.1) do
        EM.stop
      end
    }
  end
  
  
   
end
