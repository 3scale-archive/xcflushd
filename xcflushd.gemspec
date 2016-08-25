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
  spec.description   = %q{Daemon for flushing XC reports to 3scale.}
  spec.homepage      = "https://github.com/3scale/xcflushd"

  spec.license       = "Apache-2.0"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.1.0'

  spec.add_runtime_dependency "3scale_client", "= 2.6.1"

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 11.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "fakeredis", "~> 0.5.0"
  spec.add_development_dependency "simplecov", "~> 0.12.0"
end
