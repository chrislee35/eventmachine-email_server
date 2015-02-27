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
require 'dnsbl/client'

class TestEmailServer < Minitest::Test
  def run_test(userstore, emailstore)
    EM.run {
      pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
			timer = EventMachine::Timer.new(0.1) do
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
          assert_equal("250", ret.status)
        end
      end
			timer2 = EventMachine::Timer.new(0.2) do
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
      
			timer3 = EventMachine::Timer.new(0.3) do
        Thread.new do
          pop = Net::POP3.APOP(true).new('localhost',2110)
          pop.start("chris","chris")
          assert(pop.mails.empty?)
        end
      end
      
      timer4 = EventMachine::Timer.new(0.4) do
        EM.stop
      end
    }  
  end
  
  def test_memory_store
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    userstore << User.new(1, "chris", "chris", "chris@example.org")
    run_test(userstore, emailstore)
  end
  
  def test_sqlite3_store
    s = SQLite3::Database.new("test/test.sqlite3")
    userstore = Sqlite3UserStore.new(s)
    emailstore = Sqlite3EmailStore.new(s)
    userstore << User.new(1, "chris", "chris", "chris@example.org")
    run_test(userstore, emailstore)
  end
  
  def test_graylisting
    EM.run {
      SMTPServer.graylist(Hash.new)
      userstore = MemoryUserStore.new
      emailstore = MemoryEmailStore.new
      userstore << User.new(1, "chris", "chris", "chris@example.org")
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      from = "friend@example.org"
      to = "chris@example.org"
      msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do 
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("451", ret.status)
        end
      end
      timer2 = EventMachine::Timer.new(0.2) do
        Thread.new do 
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("250", ret.status)
        end
      end
      timer4 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
      
    }
  end
 
  def test_ratelimit
    EM.run {
      config = {
        'default' => RateLimit::Config.new('default', 2, 2, -2, 1, 1, 1),
      }
      storage = RateLimit::Memory.new
      rl = RateLimit::BucketBased.new(storage, config, 'default')
      SMTPServer.ratelimiter(rl)
      userstore = MemoryUserStore.new
      emailstore = MemoryEmailStore.new
      userstore << User.new(1, "chris", "chris", "chris@example.org")
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      from = "friend@example.org"
      to = "chris@example.org"
      msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          3.times do
            smtp = Net::SMTP.start('localhost', 2025)
            smtp.send_message msg, from, to
          end
        end
      end
      timer4 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
      
    }
  end
  
  def test_reject_list
    EM.run {
      userstore = MemoryUserStore.new
      emailstore = MemoryEmailStore.new
      userstore << User.new(1, "chris", "chris", "chris@example.org")
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore

      from = "friend@example.org"
      to = "chris@example.org"
      msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("250", ret.status)
          SMTPServer.reject_filters << /remember/
        end
      end
      timer2 = EventMachine::Timer.new(0.2) do
        Thread.new do
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("451", ret.status)
        end
      end
      timer4 = EventMachine::Timer.new(0.3) do
        EM.stop
      end
      
    }
  end
  
  def test_dnsbl
    EM.run {
      dnsbl = DNSBL::Client.new
      SMTPServer.dnsbl(dnsbl)
      userstore = MemoryUserStore.new
      emailstore = MemoryEmailStore.new
      userstore << User.new(1, "chris", "chris", "chris@example.org")
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore

      from = "friend@example.org"
      to = "chris@example.org"
      msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("250", ret.status)
          EM.stop
        end
      end      
    }
  end
  
  def test_spf
    return
    EM.run {
      SMTPServer.dnsbl(dnsbl)
      userstore = MemoryUserStore.new
      emailstore = MemoryEmailStore.new
      userstore << User.new(1, "chris", "chris", "chris@example.org")
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore

      from = "friend@example.org"
      to = "chris@example.org"
      msg = "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
"
      
      timer = EventMachine::Timer.new(0.1) do
        Thread.new do
          smtp = Net::SMTP.start('localhost', 2025)
          ret = smtp.send_message msg, from, to
          assert_equal("250", ret.status)
          EM.stop
        end
      end      
    }
  end
  
  def test_example
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
	
    dnsbl = DNSBL::Client.new
	
  	SMTPServer.reverse_ptr_check(true)
  	SMTPServer.graylist(Hash.new)
  	SMTPServer.ratelimiter(rl)
    SMTPServer.dnsbl(dnsbl)	
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
