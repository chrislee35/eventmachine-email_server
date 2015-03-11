# EventMachine::EmailServer

This provides an EventMachine-based implementation of POP3 and SMTP services--primarily for use within the Rubot framework.  However, as I add features, this might come in handy for other people as well (might make a good spamtrap).
 
There are several email and user backends so that the POP3 and SMTP servers can share: Memory, Sqlite3, and Null. (In the future, I plan to move Sqlite3 support into an external module and add filesystem storage as an external module as well.)

The SMTP server currently only receives mail as an end-host (no relay or sending) and does no fancy routing of email (e.g., aliases and procmail).  It does, however, have graylisting, DNS PTR checks, DNSBL checks, rate limiting, SPF checking, simple filters, and a baysian classifier.

Writing a full-featured mail server is a multi-year, multi-person project.  I would need some help.  If you're interested, let me know.

Potential features if people request them:

* SSL, StartTLS, Peer authentication (medium)
* Cram-MD5-based authentication (medium)
* IMAP (hard)
* Create a launcher in bin/ and parse configuration files (easy)
* Domain-Keys (hard, unless I find a lib that does it)
* Relay (this is easy to implement, but hard to get right)
* Aliases (easy)
* Logging (easiest)
 
## Installation

Add this line to your application's Gemfile:

```ruby
gem 'eventmachine-email_server'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install eventmachine-email_server

## Usage

Simple usage:

	require 'eventmachine'
	require 'eventmachine/email_server'
	include EventMachine::EmailServer
    EM.run {
      pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
	}

Everything turned on:

    require 'eventmachine'
    require 'eventmachine/email_server'
    include EventMachine::EmailServer
    require 'ratelimit/bucketbased'
	
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


## Contributing

1. Fork it ( https://github.com/[my-github-username]/eventmachine-email_server/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
