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
require 'fileutils'

$dns_port = 53

class EventMachine::DNS::Socket < EventMachine::Connection
  def send_packet(pkt)
    send_datagram(pkt, nameserver, $dns_port)
  end
end

class EmailTemplate < Struct.new(:from, :to, :msg); end

class TestEmailServer < Minitest::Test
  def setup
    @test_vector = Proc.new { |test_name|
      puts "***** #{test_name} *****"
      (test_name.to_s =~ /test/)
    }
    @spam_email = EmailTemplate.new("friend@example.org", "chris@example.org", "From: friend@example.org
To: chris@example.org
Subject: What to do when you're not doing.

Could I interest you in some cialis or levitra?
")
    @ham_email = EmailTemplate.new("friend@example.org", "chris@example.org", "From: friend@example.org
To: chris@example.org
Subject: Good show

Have you seen the latest Peppa Pig?
")
    @default_email = EmailTemplate.new("friend@example.org", "chris@example.org", "From: friend@example.org
To: chris@example.org
Subject: Can't remember last night

Looks like we had fun!
")
    @pool = EM::Pool.new
    SMTPServer.reset
    remove_scraps
    $dns_port = 53
  end

  def remove_scraps
    FileUtils.remove_dir("test/test.classifier", true)
  end

  def teardown
    remove_scraps
  end

  def setup_user(userstore)
    userstore << User.new(1, "chris", "chris", "chris@example.org")
  end

  def start_servers(userstore, emailstore)
    pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
    smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
  end


  def send_email(email=@default_email, &callback)
    smtp_dispatcher = EventMachine::ThreadedResource.new do
      smtp = Net::SMTP.new('localhost', 2025)
    end

    @pool.add smtp_dispatcher

    @pool.perform do |dispatcher|
      completion = dispatcher.dispatch do |smtp|
        ret = nil
        smtp.start do |s|
          begin
            ret = s.send_message email.msg, email.from, email.to
          rescue => e
            ret = "451"
          end
          begin
            smtp.quit
          rescue => e
          end
        end
        if ret.respond_to? :status
          ret = ret.status
        end
        ret
      end

      completion.callback do |result|
        callback.call(result)
      end

      completion
    end
  end

  def pop_email(&callback)

    pop3_dispatcher = EventMachine::ThreadedResource.new do
    end

    @pool.add pop3_dispatcher

    @pool.perform do |dispatcher|
      completion = dispatcher.dispatch do |pop|
        pop = Net::POP3.APOP(true).new('localhost',2110)
        pop.start("chris","chris")
        answers = Array.new
        answers << pop.mails.empty?
        if not pop.mails.empty?
          pop.each_mail do |m|
            answers << m.mail
            m.delete
          end
        end
        pop.finish
        answers
      end

      completion.callback do |answers|
        callback.call(answers)
      end

      completion
    end
  end

  def run_test(userstore, emailstore)
    EM.run {
      start_servers(userstore, emailstore)
      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      EM::Timer.new(0.1) do
        pop_email do |answers|
          assert_equal(true, answers[0])
          send_email do |result|
            assert_equal("250", result)
            pop_email do |answers|
              assert_equal(false, answers[0])
              assert_equal(@default_email.msg.gsub(/[\r\n]+/,"\n"), answers[1].gsub(/[\r\n]+/,"\n"))
              pop_email do |answers|
                assert_equal(true, answers[0])
                EM.stop
              end
            end
          end
        end
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
  
  def test_graylisting
    return unless @test_vector.call(__method__)
    SMTPServer.graylist(Hash.new)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end

      timer = EventMachine::Timer.new(0.1) do
        send_email do |result|
          assert_equal("451", result)
          send_email do |result|
            assert_equal("250", result)
            EM.stop
          end
        end
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
    SMTPServer.ratelimiter(rl)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore

      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      timer = EventMachine::Timer.new(0.1) do
        send_email do |result|
          assert_equal("250", result)
          send_email do |result|
            assert_equal("250", result)
            send_email do |result|
              assert_equal("451", result)
              EM.stop
            end
          end
        end
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

      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      timer = EventMachine::Timer.new(0.1) do
        send_email do |result|
          assert_equal("250", result)
          SMTPServer.reject_filters << /remember/
          send_email do |result|
            assert_equal("451", result)
            EM.stop
          end
        end
      end
    }
  end

  def test_dnsbl
    return unless @test_vector.call(__method__)

    $dns_port = 2053

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
    SMTPServer.dnsbl_check(true)

    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    EM.run {
      EM::open_datagram_socket "0.0.0.0", 2053, EventMachine::DNSBL::Server, memzone
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      timer = EventMachine::Timer.new(0.1) do
        send_email do |result|
          assert_equal("250", result)
          memzone.add_dnsblresource(
            EventMachine::DNSBL::Zone::DNSBLResourceRecord.new(
              "example.com",
              /\d+\.0\.0\.127$/,
              300,
              Resolv::DNS::Resource::IN::A.new("127.0.0.4"),
              Time.now.to_i + 3600
            )
          )
          send_email do |result|
            assert_equal("451", result)
            EM.stop
          end
        end
      end
    }
  end

  def test_spf
    return unless @test_vector.call(__method__)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)

    SMTPServer.spf_check(true)
    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      timer = EventMachine::Timer.new(0.1) do
        send_email do |result|
          assert_equal("451", result)
          EM.stop
        end
      end
    }
  end

  def test_classifier
    return unless @test_vector.call(__method__)
    userstore = MemoryUserStore.new
    emailstore = MemoryEmailStore.new
    setup_user(userstore)
    classifier = EventMachine::EmailServer::Classifier.new("test/test.classifier", [:spam, :ham], [:spam])
    classifier.train(:spam, "Amazing pillz viagra cialis levitra staxyn")
    classifier.train(:ham, "Big pigs make great bacon")
    SMTPServer.classifier(classifier)
    EM.run {
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      EM::Timer.new(10) do
        fail "Test timed out"
        EM.stop
      end
      timer = EventMachine::Timer.new(0.1) do
        send_email(@spam_email) do |result|
          assert_equal("451", result)
          send_email(@ham_email) do |result|
            assert_equal("250", result)
            EM.stop
          end
        end
      end
    }
  end

  def test_example
    return unless @test_vector.call(__method__)
    #require 'eventmachine'
    #require 'eventmachine/email_server'
    #include EventMachine::EmailServer
    #require 'ratelimit/bucketbased'

    userstore = MemoryUserStore.new()
    emailstore = MemoryEmailStore.new()
    userstore << User.new(1, "chris", "chris", "chris@example.org")

    config = {
      'default' => RateLimit::Config.new('default', 2, 2, -2, 1, 1, 1),
    }
    storage = RateLimit::Memory.new
    rl = RateLimit::BucketBased.new(storage, config, 'default')

    classifier = EventMachine::EmailServer::Classifier.new("test/test.classifier", [:spam, :ham], [:spam])
    classifier.train(:spam, "Amazing pillz viagra cialis levitra staxyn")
    classifier.train(:ham, "Big pigs make great bacon")

    SMTPServer.reverse_ptr_check(true)
    SMTPServer.graylist(Hash.new)
    SMTPServer.ratelimiter(rl)
    SMTPServer.dnsbl_check(true)
    SMTPServer.spf_check(true)
    SMTPServer.reject_filters << /viagra/i
    SMTPServer.classifier(classifier)

    EM.run {
      pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
      timer = EventMachine::Timer.new(0.1) do
        EM.stop
      end
    }
  end

end
