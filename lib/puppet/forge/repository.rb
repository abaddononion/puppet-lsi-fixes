require 'net/http'
require 'digest/sha1'
require 'uri'

class Puppet::Forge
  # = Repository
  #
  # This class is a file for accessing remote repositories with modules.
  class Repository
    attr_reader :uri, :cache

    # Instantiate a new repository instance rooted at the +url+.
    # The agent will report +consumer_version+ in the User-Agent to
    # the repository.
    def initialize(url, consumer_version)
      @uri = url.is_a?(::URI) ? url : ::URI.parse(url.sub(/^(?!https?:\/\/)/, 'http://'))
      @cache = Cache.new(self)
      @consumer_version = consumer_version
    end

    # Read HTTP proxy configurationm from Puppet's config file, or the
    # http_proxy environment variable.
    def http_proxy_env
      proxy_env = ENV["http_proxy"] || ENV["HTTP_PROXY"] || nil
      begin
        return URI.parse(proxy_env) if proxy_env
      rescue URI::InvalidURIError
        return nil
      end
      return nil
    end

    def http_proxy_host
      env = http_proxy_env

      if env and env.host then
        return env.host
      end

      if Puppet.settings[:http_proxy_host] == 'none'
        return nil
      end

      return Puppet.settings[:http_proxy_host]
    end

    def http_proxy_port
      env = http_proxy_env

      if env and env.port then
        return env.port
      end

      return Puppet.settings[:http_proxy_port]
    end

    # Return a Net::HTTPResponse read for this +request_path+.
    def make_http_request(request_path)
      request = Net::HTTP::Get.new(request_path, { "User-Agent" => user_agent })
      if ! @uri.user.nil? && ! @uri.password.nil?
        request.basic_auth(@uri.user, @uri.password)
      end
      return read_response(request)
    end

    # Return a Net::HTTPResponse read from this HTTPRequest +request+.
    def read_response(request)
      begin
        Net::HTTP::Proxy(
            http_proxy_host,
            http_proxy_port
            ).start(@uri.host, @uri.port) do |http|
          http.request(request)
        end
      rescue Errno::ECONNREFUSED, SocketError
        msg = "Error: Could not connect to #{@uri}\n"
        msg << "  There was a network communications problem\n"
        msg << "    Check your network connection and try again\n"
        Puppet.err msg
        exit(1)
      end
    end

    # Return the local file name containing the data downloaded from the
    # repository at +release+ (e.g. "myuser-mymodule").
    def retrieve(release)
      return cache.retrieve(@uri + release)
    end

    # Return the URI string for this repository.
    def to_s
      return @uri.to_s
    end

    # Return the cache key for this repository, this a hashed string based on
    # the URI.
    def cache_key
      return @cache_key ||= [
        @uri.to_s.gsub(/[^[:alnum:]]+/, '_').sub(/_$/, ''),
        Digest::SHA1.hexdigest(@uri.to_s)
      ].join('-')
    end

    def user_agent
      "#{@consumer_version} Puppet/#{Puppet.version} (#{Facter.value(:operatingsystem)} #{Facter.value(:operatingsystemrelease)}) #{ruby_version}"
    end
    private :user_agent

    def ruby_version
      # the patchlevel is not available in ruby 1.8.5
      patch = defined?(RUBY_PATCHLEVEL) ? "-p#{RUBY_PATCHLEVEL}" : ""
      "Ruby/#{RUBY_VERSION}#{patch} (#{RUBY_RELEASE_DATE}; #{RUBY_PLATFORM})"
    end
    private :ruby_version
  end
end
