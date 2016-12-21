# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xcflushd/version'

Gem::Specification.new do |spec|
  spec.name          = "xcflushd"
  spec.version       = Xcflushd::VERSION
  spec.authors       = ["Alejandro Martinez Ruiz", "David Ortiz Lopez"]
  spec.email         = ["support@3scale.net"]

  spec.summary       = %q{Daemon for flushing XC reports to 3scale.}
  spec.description   = "xcflushd is a daemon that connects to a Redis database " \
                       "containing 3scale's XC API Management data and flushes " \
                       "it to the 3scale service for cached reporting and " \
                       "authorizations. Check https://github.com/3scale/apicast-xc" \
                       " for an implementation of a 3scale's XC gateway."
  spec.homepage      = "https://github.com/3scale/xcflushd"

  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1.0'

  spec.add_runtime_dependency "3scale_client", "~> 2.10"
  spec.add_runtime_dependency "gli", "= 2.14.0"
  spec.add_runtime_dependency "redis", "= 3.3.2"
  spec.add_runtime_dependency "hiredis", "= 0.6.1"
  spec.add_runtime_dependency "concurrent-ruby", "1.0.2"
  spec.add_runtime_dependency "net-http-persistent", "2.9.4"
  spec.add_runtime_dependency "daemons", "= 1.2.4"

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 11.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "fakeredis", "~> 0.6.0"
  spec.add_development_dependency "simplecov", "~> 0.12.0"
  spec.add_development_dependency "rubocop", "~> 0.46.0"
end
