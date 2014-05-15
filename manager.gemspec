# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'manager/version'

Gem::Specification.new do |spec|
  spec.name          = "manager"
  spec.version       = Manager::VERSION
  spec.authors       = ["Ryan Michael"]
  spec.email         = ["kerinin@gmail.com"]
  spec.summary       = %q{Manage your cluster}
  spec.description   = %q{Cluster process management daemon}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "assembler"
  spec.add_dependency "consistent-hashing"
  spec.add_dependency "daemons"
  spec.add_dependency "faraday", '~> 0.8.9'
  spec.add_dependency "faraday_middleware", '~> 0.9.0'


  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "fuubar"
  spec.add_development_dependency "webmock"
end
