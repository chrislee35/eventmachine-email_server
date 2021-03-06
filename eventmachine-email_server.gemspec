# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'eventmachine/email_server/version'

Gem::Specification.new do |spec|
  spec.name          = "eventmachine-email_server"
  spec.version       = EventMachine::EmailServer::VERSION
  spec.authors       = ["chrislee35"]
  spec.email         = ["rubygems@chrislee.dhs.org"]
  spec.summary       = %q{EventMachine-based implementations of a POP3 and SMTP server}
  spec.description   = %q{Simple POP3 and SMTP implementation in EventMachine for use in the Rubot framework}
  spec.homepage      = "https://github.com/chrislee35/eventmachine-email_server/"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "eventmachine", ">= 0.12.10"
  spec.add_runtime_dependency "ratelimit-bucketbased", ">= 0.0.1"
  spec.add_runtime_dependency "eventmachine-dnsbl", ">= 0.0.2"
  spec.add_runtime_dependency "spf", ">= 0.0.44"
  spec.add_runtime_dependency "classifier", ">= 1.3.4"
  spec.add_runtime_dependency "rb-gsl", ">= 1.16.0.4"
  spec.add_runtime_dependency "fast-stemmer", ">= 1.0.2"
  spec.add_runtime_dependency "madeleine", ">= 0.9.0"
  spec.add_development_dependency "minitest", "~> 5.5"
  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", "~> 10.0"
end
