require 'rack'
require 'rack/utils'
require 'rack/mime'
require 'mime/types'
require 'digest'
require './lib/rack/static_media/version'

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

      # decode once; reject bad encodings
      begin
        rel = ::Rack::Utils.unescape_path(rel)
      rescue ArgumentError
        return bad_request('Bad path encoding')
      end

      # normalize + forbid traversal
      return bad_request('NUL in path') if rel.include?("\u0000")

      path = safe_join(@root, rel)
      return forbidden unless path

      # if directory, try index files
      if File.directory?(path)
        path = @index_files.map { |ix| File.join(path, ix) }.find { |p| File.file?(p) }
        return not_found unless path
      end

      return not_found unless File.file?(path)

      # extension whitelist
      ext = File.extname(path).downcase
      return forbidden unless allowed_extension?(ext, path)

      # allow/deny lists (regexes or strings)
      return forbidden if @deny_list&.any? { |pat| match_pat?(pat, path) }
      if @allow_list && !@allow_list.any? { |pat| match_pat?(pat, path) }
        return forbidden
      end

      # optional signature check (?sig=..., ?exp=...)
      if @secret
        return unauthorized unless valid_signature?(req, path)
      end

      # HEAD/GET only
      return method_not_allowed unless %w[GET HEAD].include?(req.request_method)

      # caching headers
      headers = { 'Cache-Control' => @cache_control }
      stat    = File.stat(path)
      if @etag_enabled
        et = weak_etag(stat)
        headers['ETag'] = et
        # 304 if If-None-Match matches
        inm = req.get_header('HTTP_IF_NONE_MATCH')
        return [304, headers, []] if inm && Rack::Utils.secure_compare(inm, et)
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

      # full file
      headers['Content-Length'] = stat.size.to_s
      body = stream_file(path, head: req.head?)
      [200, headers, body]
    rescue => e
      # don’t leak internal paths/errors
      [500, {'Content-Type' => 'text/plain'}, ["StaticMedia error\n"]]
    end

    private

    def mount_hit?(path)
      return false unless path.start_with?(@mount)
      # allow exact mount (serves index) or below
      path == @mount.chomp('/') || true
    end

    def allowed_extension?(ext, path)
      return true if @allowed_ext.include?(ext)
      # allow html if explicitly indexed
      @index_files.any? { |ix| path.end_with?("/#{ix}") }
    end

    def mime_for(ext)
      types = MIME::Types.type_for(ext)
      types.first&.to_s
    end

    def stream_file(path, offset: 0, length: nil, head: false)
      return [] if head
      io = File.open(path, 'rb')
      io.seek(offset) if offset && offset > 0
      if length
        ::Rack::BodyProxy.new(io) do |f|
          # nothing — BodyProxy will close it
        end.tap do |proxy|
          def proxy.each
            remaining = @length
            while remaining > 0
              chunk = @io.read([8192, remaining].min)
              break unless chunk
              remaining -= chunk.bytesize
              yield chunk
            end
          end
          proxy.instance_variable_set(:@io, io)
          proxy.instance_variable_set(:@length, length)
        end
      else
        ::Rack::File::Iterator.new(io)
      end
    end

    def weak_etag(stat)
      %W[W/ "#{stat.size}-#{stat.mtime.to_i}"].join
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
