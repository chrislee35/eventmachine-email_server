# EventMachine::EmailServer

This provides an EventMachine-based implementation of POP3 and SMTP services--primarily for use within the Rubot framework.  However, as I add features, this might come in handy for other people as well.
 
There are several email and user backends so that the POP3 and SMTP servers can share: Memory, Sqlite3, and Null.

The SMTP server currently only receives mail as an end-host (no relay or sending) and does no fancy routing of email (e.g., aliases and procmail).  It does, however, have graylisting, DNS PTR checks, DNSBL checks, rate limiting, and simple filters.

Writing a full-featured mail server is a multi-year, multi-person project.  I would need some help.

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

	require 'eventmachine/email_server'
	include EventMachine::EmailServer
    EM.run {
      pop3 = EventMachine::start_server "0.0.0.0", 2110, POP3Server, "example.org", userstore, emailstore
      smtp = EventMachine::start_server "0.0.0.0", 2025, SMTPServer, "example.org", userstore, emailstore
	}

Everything turned on:

    require 'eventmachine/email_server'
    include EventMachine::EmailServer
    require 'ratelimit/bucketbased'
    require 'dnsbl/client'
    require 'sqlite3'
	
    s = SQLite3::Database.new("test/test.sqlite3")
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
    }


## Contributing

If we want this to be "professional":
*EventMachine-based SPF Checking
*EventMachine-based DNSBL::Client
*Abstract filtering into a class with a callback so that all sorts of filtering (e.g., baysian) could be done
*Create a launcher in bin/ and parse configuration files
*StartTLS
*SSL
*CRAM-MD5
*Domain-Keys
*Relay (this is easy to implement, but hard to get right)
*Aliases
*Logging

1. Fork it ( https://github.com/[my-github-username]/eventmachine-email_server/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
