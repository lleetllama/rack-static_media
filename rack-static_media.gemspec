require_relative 'lib/rack/static_media/version'

Gem::Specification.new do |spec|
  spec.name                  = 'rack-static_media'
  spec.version               = Rack::StaticMedia::VERSION
  spec.authors               = ['lleetllama']
  spec.email                 = ['lleetllama@gmail.com']

  spec.summary               = 'Secure, cache-friendly Rack middleware to serve media outside /public'
  spec.description           = 'Mount a safe file server at any path with extension whitelisting, range requests, and strong caching.'
  spec.license               = 'MIT'
  spec.homepage              = 'https://github.com/lleetllama/rack-static_media'

  spec.required_ruby_version = '>= 3.1'
  spec.require_paths         = ['lib']

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").grep(%r{\A(lib|README|LICENSE|CHANGELOG)})
  end

  spec.add_dependency 'mime-types', '>= 3.0'
  spec.add_dependency 'rack', '>= 3.0'
  spec.add_dependency 'railties', '>= 6.1'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => 'https://github.com/lleetllama/rack-static_media',
    'changelog_uri' => 'https://github.com/lleetllama/rack-static_media/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/lleetllama/rack-static_media/issues',
    'rubygems_mfa_required' => 'true',
    # "allowed_push_host" => "https://rubygems.org"
  }
end
