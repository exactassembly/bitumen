# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bitumen/version'

Gem::Specification.new do |spec|
    spec.name          = "bitumen"
    spec.version       = Bitumen::VERSION
    spec.authors       = ["Theodore Vaida"]
    spec.email         = ["ted@xassembly.com"]
    spec.summary       = %q{Bitumen - Yocto construction automation}
    spec.description   = %q{Bitumen provides glue for building Yocto Embedded Linux with Rake and Docker}
    spec.homepage      = "https://github.com/exactassembly/bitumen"
    spec.license       = "GPLv2"

    spec.files         = `git ls-files -z`.split("\x0")
    spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
    spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
    spec.require_paths = ["lib"]

    spec.add_development_dependency "bundler", "~> 1.7"
    spec.add_development_dependency "rake", "~> 10.0"
    spec.add_runtime_dependency "rake", "~> 10.0"
    spec.add_runtime_dependency "rummager", "~> 0.5.14"
end
