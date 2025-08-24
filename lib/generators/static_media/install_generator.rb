require 'rails/generators'

module StaticMedia
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path('templates', __dir__)

    def copy_initializer
      template 'static_media.rb', 'config/initializers/static_media.rb'
    end
  end
end