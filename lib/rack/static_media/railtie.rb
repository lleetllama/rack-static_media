# lib/rack/static_media/railtie.rb
require 'rails/railtie'

module Rack
  class StaticMedia
    class Railtie < ::Rails::Railtie
      generators do
        require 'generators/static_media/install/install_generator'
      end
    end
  end
end
