require "rails/railtie"

module Rack
  class StaticMedia
    class Railtie < ::Rails::Railtie
      # no-op by default; you’ll add a Rails initializer in the host app
    end
  end
end