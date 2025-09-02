require 'rack'
require 'rack/utils'
require 'rack/mime'
require 'mime/types'
require 'digest'
require 'openssl'
require 'rack/body_proxy'

module Rack
  class StaticMedia
    DEFAULT_ALLOWED = %w[.png .jpg .jpeg .webp .gif .bmp .svg .mp4 .webm .mp3 .wav .flac .pdf].freeze

    def initialize(
      app, root:, mount: '/media', allowed_ext: DEFAULT_ALLOWED,
      cache_control: 'public, max-age=31536000', etag: true, last_modified: true,
      signing_secret: nil, allow_list: nil, deny_list: nil,
      index_filenames: ['index.html']
    )

      @app            = app
      @root           = File.expand_path(root.to_s)
      @mount          = mount.end_with?('/') ? mount : "#{mount}/"
      @allowed_ext    = allowed_ext&.map(&:downcase) || DEFAULT_ALLOWED
      @cache_control  = cache_control
      @etag_enabled   = etag
      @lm_enabled     = last_modified
      @secret         = signing_secret
      @allow_list     = Array(allow_list) if allow_list
      @deny_list      = Array(deny_list) if deny_list
      @index_files    = Array(index_filenames)
    end

    def call(env)
      req = ::Rack::Request.new(env)

      return @app.call(env) unless mount_hit?(req.path_info)

      # strip mount prefix
      rel = req.path_info.sub(@mount, '')
      rel = '' if rel == '/'

      begin
        rel = ::Rack::Utils.unescape_path(rel)
      rescue ArgumentError
        # CHANGED: fall through so Rails can render its error page
        return @app.call(env)
      end

      return @app.call(env) if rel.include?("\u0000") # CHANGED: fall through on bad path

      path = safe_join(@root, rel)
      return @app.call(env) unless path # CHANGED: traversal => fall through

      # if directory, try index files
      if File.directory?(path)
        path = @index_files.map { |ix| File.join(path, ix) }.find { |p| File.file?(p) }
        return @app.call(env) unless path # CHANGED: no index => fall through
      end

      return @app.call(env) unless File.file?(path) # CHANGED: miss => fall through

      # extension whitelist
      ext = File.extname(path).downcase
      unless allowed_extension?(ext, path)
        return @app.call(env) # CHANGED: let Rails handle weird extensions
      end

      # allow/deny lists
      if @deny_list&.any? { |pat| match_pat?(pat, path) }
        return @app.call(env) # CHANGED
      end
      if @allow_list && !@allow_list.any? { |pat| match_pat?(pat, path) }
        return @app.call(env) # CHANGED
      end

      # optional signature check (?sig, ?exp)
      if @secret
        return [401, {'Content-Type' => 'text/plain', 'X-Static-Media' => 'sig-fail'}, ['Unauthorized']] unless valid_signature?(req, path)
      end

      # HEAD/GET only
      return @app.call(env) unless %w[GET HEAD].include?(req.request_method) # CHANGED

      headers = {
        'Cache-Control' => @cache_control,
        'X-Static-Media' => 'hit',
        'Accept-Ranges' => 'bytes'
      }

      stat = File.stat(path)

      if @etag_enabled
        et = weak_etag(stat)
        headers['ETag'] = et
        inm = req.get_header('HTTP_IF_NONE_MATCH')
        if inm
          client_etags = inm.split(',').map(&:strip)
          return [304, headers, []] if client_etags.any? { |v| Rack::Utils.secure_compare(v, et) }
        end
      end

      if @lm_enabled
        headers['Last-Modified'] = stat.mtime.httpdate
        ims = req.get_header('HTTP_IF_MODIFIED_SINCE')
        if ims
          t = Time.httpdate(ims) rescue nil
          return [304, headers, []] if t && stat.mtime <= t
        end
      end

      # content type
      headers['Content-Type'] = mime_for(ext) || Rack::Mime.mime_type(ext, 'application/octet-stream')

      # Range support
      range_hdr = req.get_header('HTTP_RANGE')
      if range_hdr
        ranges = Rack::Utils.byte_ranges(env, stat.size)
        if ranges && ranges.length == 1
          range = ranges[0]
          offset, length = range.begin, range.end - range.begin + 1
          headers['Content-Range'] = "bytes #{range.begin}-#{range.end}/#{stat.size}"
          headers['Content-Length'] = length.to_s
          body = stream_file(path, offset: offset, length: length, head: req.head?)
          return [206, headers, body]
        end
      end

      headers['Content-Length'] = stat.size.to_s
      body = stream_file(path, head: req.head?)
      [200, headers, body]

    rescue => e
      warn "[StaticMedia] #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" if ENV['STATIC_MEDIA_DEBUG'] == '1'

      # CHANGED: prefer re-raise in any non-production Rack env, even if Rails isn't loaded yet
      rack_env = (ENV['RACK_ENV'] || 'development').to_s
      rails_nonprod = defined?(Rails) && !Rails.env.production?

      if rails_nonprod || rack_env != 'production'
        raise e
      else
        [500, {'Content-Type' => 'text/plain', 'X-Static-Media' => 'error'}, ["StaticMedia error\n"]]
      end
    end



    private

    def mount_hit?(path)
      # Allow exact mount (e.g. /media -> /media/index.html) or any path under /media/
      path == @mount.chomp('/') || path.start_with?(@mount)
    end

    def allowed_extension?(ext, path)
      return true if @allowed_ext.include?(ext)
      @index_files.any? { |ix| path.end_with?("/#{ix}") } # allow explicit index html
    end

    def mime_for(ext)
      # ext like ".png" -> "png"
      key = ext.to_s.sub(/\A\./, '')
      types = MIME::Types.type_for(key)
      types.first&.to_s
    end

    def stream_file(path, offset: 0, length: nil, head: false)
      return [] if head
      file = File.open(path, 'rb')
      file.seek(offset.to_i) if offset && offset.to_i > 0
      enum = Enumerator.new do |y|
        if length
          remaining = length.to_i
          while remaining > 0
            chunk = file.read([8192, remaining].min)
            break unless chunk
            remaining -= chunk.bytesize
            y << chunk
          end
        else
          while (chunk = file.read(8192))
            y << chunk
          end
        end
      end
      ::Rack::BodyProxy.new(enum) { file.close }
    end

    def weak_etag(stat)
      %Q{W/"#{stat.size}-#{stat.mtime.to_i}"}
    end

    def bad_request(msg)    = [400, {'Content-Type' => 'text/plain'}, [msg]]
    def forbidden           = [403, {'Content-Type' => 'text/plain'}, ['Forbidden']]
    def unauthorized        = [401, {'Content-Type' => 'text/plain'}, ['Unauthorized']]
    def not_found           = [404, {'Content-Type' => 'text/plain'}, ['Not Found']]
    def method_not_allowed  = [405, {'Allow' => 'GET, HEAD', 'Content-Type' => 'text/plain'}, ['Method Not Allowed']]

    # resolve and ensure target stays under @root
    def safe_join(root, rel)
      cleaned = rel.sub(/\A\/*/, '') # strip leading slashes
      candidate = File.expand_path(File.join(root, cleaned))
      root_d = root
      cand_d = candidate
      if Gem.win_platform?
        root_d = root.downcase
        cand_d = candidate.downcase
      end
      return nil unless cand_d.start_with?(root_d)

      candidate
    end

    def match_pat?(pat, path)
      pat.is_a?(Regexp) ? path.match?(pat) : path.include?(pat.to_s)
    end

    # ?sig=HMAC_SHA256(path + exp) & ?exp=unix_timestamp
    def valid_signature?(req, path)
      sig = req.params['sig']
      exp = req.params['exp']
      return false unless sig && exp&.match?(/\A\d+\z/)
      return false if Time.now.to_i > exp.to_i

      data = "#{path}#{exp}"
      expected = OpenSSL::HMAC.hexdigest('SHA256', @secret, data)
      Rack::Utils.secure_compare(expected, sig)
    end
  end
end
