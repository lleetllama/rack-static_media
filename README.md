# rack-static_media
Mount a safe file server at any path with extension whitelisting, range requests, and strong caching.

Rack middleware for serving static files from arbitrary directories with strong caching and security features.

## Features
- Mount at any path (default `/media`).
- Extension whitelist to avoid serving unwanted file types.
- Optional allow/deny lists for fine‑grained control.
- Support for `GET` and `HEAD` requests with byte‑range responses.
- ETag and `Last-Modified` headers for cache validation.
- Optional HMAC signing of URLs to restrict access.
- Compatible with plain Rack apps or Rails via a Railtie.

## Installation
Add the gem to your application:

```ruby
# Gemfile
gem 'rack-static_media', git: 'https://github.com/lleetllama/rack-static_media'
```

Or install it directly:

```bash
gem install rack-static_media
```

## Basic Usage
Use the middleware in a Rack app:

```ruby
require 'rack/static_media'

app = Rack::Builder.new do
  use Rack::StaticMedia, root: '/var/www/uploads', mount: '/media'
  run MyRackApp
end
```

The above serves files from `/var/www/uploads` under the `/media` URL path.

### Rails
Use the installer to generate a ready-to-use initializer:

```bash
bin/rails generate static_media:install --mount=/media
```

This creates `config/initializers/static_media.rb` with sensible defaults, which you can customize as needed. The generated file mounts the middleware like so:

```ruby
Rails.application.config.middleware.use(
  Rack::StaticMedia,
  root: Rails.root.join('storage'),
  mount: '/media'
)
```

## Configuration Options
| Option | Default | Description |
| ------ | ------- | ----------- |
| `root` | – | Filesystem directory to serve. |
| `mount` | `/media` | URL prefix at which files are exposed. |
| `allowed_ext` | common image/audio/video/pdfs | Whitelisted extensions. |
| `cache_control` | `public, max-age=31536000` | Cache-Control header value. |
| `etag` | `true` | Enable weak ETag generation. |
| `last_modified` | `true` | Emit Last-Modified header. |
| `signing_secret` | `nil` | Enable HMAC signing of URLs. Requires `sig` and `exp` params. |
| `allow_list` / `deny_list` | `nil` | Arrays of strings or regexes to explicitly allow/deny paths. |
| `index_filenames` | `["index.html"]` | Filenames to serve when directory is requested. |

## Environment Variables
The middleware recognizes a few optional environment variables:

| Variable | Description |
| -------- | ----------- |
| `MEDIA_ROOT` | Override the filesystem directory used for media files. |
| `MEDIA_SIGNING_SECRET` | Enable HMAC URL signing by providing a secret. |
| `STATIC_MEDIA_DEBUG` | Set to `1` to log stack traces when errors occur. |

## URL Signing
When `signing_secret` is provided, requests must include `?sig=<hexdigest>&exp=<unix_ts>`. Signatures are calculated using:

```ruby
OpenSSL::HMAC.hexdigest('SHA256', secret, path + exp)
```

Requests with missing, invalid, or expired signatures return `401 Unauthorized`.

## Development
Clone the repository and run the gemspec tests (none provided yet):

```bash
bundle exec rake
```

## License
This project is released under the [MIT License](LICENSE).