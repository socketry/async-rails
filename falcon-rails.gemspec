# frozen_string_literal: true

require_relative "lib/falcon/rails/version"

Gem::Specification.new do |spec|
	spec.name = "falcon-rails"
	spec.version = Falcon::Rails::VERSION
	
	spec.summary = "Easy Falcon and Rails integration."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/falcon-rails"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/falcon-rails/",
		"source_code_uri" => "https://github.com/socketry/falcon-rails.git",
	}
	
	spec.files = Dir["{context,lib}/**/*", "*.md", base: __dir__]
	
	spec.required_ruby_version = ">= 3.2"
	
	spec.add_dependency "async-cable"
	spec.add_dependency "async-job-adapter-active_job"
	spec.add_dependency "async-websocket"
	spec.add_dependency "bake"
	spec.add_dependency "console-adapter-rails"
	spec.add_dependency "falcon"
	spec.add_dependency "live"
	
	spec.add_dependency "rails", ">= 8.0"
end
