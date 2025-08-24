require "rails/generators"

module StaticMedia
  module Install
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      class_option :mount, type: :string, default: "/media"

      def create_initializer
        template "static_media.rb", "config/initializers/static_media.rb"
      end
    end
  end
end