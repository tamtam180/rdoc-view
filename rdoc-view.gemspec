# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rdoc-view/version'

Gem::Specification.new do |gem|
  gem.name          = "rdoc-view"
  gem.version       = RDocView::VERSION
  gem.authors       = ["tamtam180"]
  gem.email         = ["kirscheless@gmail.com"]
  gem.description   = %q{Realtime RDoc viewer with WebSocket.}
  gem.summary       = %q{Realtime RDoc viewer with WebSocket.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/) - %w[.gitignore]
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency "sinatra"
  gem.add_dependency "sinatra-websocket"
  gem.add_dependency "fssm"
  gem.add_dependency "rdoc"
  gem.add_dependency "RedCloth"
end
