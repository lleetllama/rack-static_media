# lib/generators/static_media/install/install_generator.rb
require 'rails/generators'

module StaticMedia
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      class_option :mount, type: :string, default: '/media', desc: 'Mount path for the middleware'

      # Make `mount` available to the template
      def mount
        options[:mount]
      end

      def create_initializer
        template 'static_media.rb.tt', 'config/initializers/static_media.rb'
      end
    end
  end
end
