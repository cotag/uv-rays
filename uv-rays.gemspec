require File.expand_path("../lib/uv-rays/version", __FILE__)

Gem::Specification.new do |gem|
    gem.name          = "uv-rays"
    gem.version       = UvRays::VERSION
    gem.license       = 'MIT'
    gem.authors       = ["Stephen von Takach"]
    gem.email         = ["steve@cotag.me"]
    gem.homepage      = "https://github.com/cotag/uv-rays"
    gem.summary       = "Abstractions for working with Libuv"
    gem.description   = "Opinionated abstractions for Libuv"

    gem.required_ruby_version = '>= 1.9.2'
    gem.require_paths = ["lib"]

    gem.add_runtime_dependency     'libuv'
    gem.add_runtime_dependency     'bisect'
    gem.add_runtime_dependency     'tzinfo'
    gem.add_runtime_dependency     'ipaddress'
    gem.add_runtime_dependency     'addressable'

    gem.add_development_dependency 'rspec', '>= 2.14'
    gem.add_development_dependency 'rake', '>= 10.1'
    gem.add_development_dependency 'yard'

    gem.files = Dir["{lib}/**/*"] + %w(Rakefile uv-rays.gemspec README.md LICENSE)
    gem.test_files = Dir["spec/**/*"]
    gem.extra_rdoc_files = ["README.md"]
end
