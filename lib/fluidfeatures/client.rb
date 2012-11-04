
require "net/http"
require "persistent_http"
require "pre_ruby192/uri" if RUBY_VERSION < "1.9.2"
require "thread"
require "uuid"

require "fluidfeatures/app"

module FluidFeatures
  class Client

    attr_accessor :uuid, :base_uri, :logger, :last_fetch_duration

    API_REQUEST_LOG_MAX_SIZE = 200

    def initialize(base_uri, logger)

      @uuid = UUID.new.generate
      @logger = logger
      @base_uri = base_uri

      @http = ::PersistentHTTP.new(
        :name         => 'fluidfeatures',
        :logger       => logger,
        :pool_size    => 10,
        :warn_timeout => 0.25,
        :force_retry  => true,
        :url          => base_uri
      )

      @api_request_log = []
      @api_request_log_lock = ::Mutex.new

      @etags = {}
      @etags_lock = ::Mutex.new

    end

    def log_api_request(method, url, duration, status_code, err_msg)
      @api_request_log_lock.synchronize do
        @api_request_log << {
          :method => method,
          :url => url,
          :duration => duration,
          :status => status_code,
          :err => err_msg,
          :time => Time.now.to_f.round(2)
        }
        # remove older entry if too big
        if @api_request_log.size > API_REQUEST_LOG_MAX_SIZE
          @api_request_log.shift
        end
      end
    end

    def siphon_api_request_log
      request_log = nil
      @api_request_log_lock.synchronize do
        request_log = @api_request_log
        @api_request_log = []
      end
      request_log
    end

    def get(path, auth_token, url_params=nil, cache=false)
      payload = nil

      uri = URI(@base_uri + path)
      url_path = uri.path
      if url_params
        uri.query = URI.encode_www_form( url_params )
        if uri.query
          url_path += "?" + uri.query
        end
      end

      duration = nil
      status_code = nil
      err_msg = nil
      no_change = false
      success = false
      begin

        request = Net::HTTP::Get.new url_path
        request["Accept"] = "application/json"
        request['AUTHORIZATION'] = auth_token
        @etags_lock.synchronize do
          if cache and @etags.has_key? url_path
            request["If-None-Match"] = @etags[url_path][:etag]
          end
        end

        request_start_time = Time.now
        response = @http.request request
        duration = Time.now - request_start_time

        if response.is_a? Net::HTTPResponse
          status_code = response.code
          if response.is_a? Net::HTTPNotModified
            no_change = true
            success = true
          elsif response.is_a? Net::HTTPSuccess
            payload = JSON.load(response.body) rescue nil
            if cache
              @etags_lock.synchronize do
                @etags[url_path] = {
                  :etag => response["Etag"],
                  :time => Time.now
                }
              end
            end
            success = true
          else
            payload = JSON.load(response.body) rescue nil
            if payload and payload.is_a? Hash and payload.has_key? "error"
              err_msg = payload["error"]
            end
            logger.error{"[FF] Request unsuccessful for GET #{path} : #{response.class} #{status_code} #{err_msg}"}
          end
        end
      rescue PersistentHTTP::Error => err
        logger.error{"[FF] Request failed for GET #{path} : #{err.message}"}
      rescue
        logger.error{"[FF] Request failed for GET #{path} : #{status_code} #{err_msg}"}
        raise
      else
        unless no_change or payload
          logger.error{"[FF] Empty response for GET #{path} : #{status_code} #{err_msg}"}
        end
      end

      log_api_request("GET", url_path, duration, status_code, err_msg)

      return success, payload
    end

    def put(path, auth_token, payload)
      uri = URI(@base_uri + path)
      url_path = uri.path
      duration = nil
      status_code = nil
      err_msg = nil
      success = false
      begin
        request = Net::HTTP::Put.new uri_path
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request['AUTHORIZATION'] = auth_token
        request.body = JSON.dump(payload)

        request_start_time = Time.now
        response = @http.request uri, request
        duration = Time.now - request_start_time

        raise "expected Net::HTTPResponse" if not response.is_a? Net::HTTPResponse
        status_code = response.code
        if response.is_a? Net::HTTPSuccess
          success = true
        else
          response_payload = JSON.load(response.body) rescue nil
          if response_payload.is_a? Hash and response_payload.has_key? "error"
            err_msg = response_payload["error"]
          end
          logger.error{"[FF] Request unsuccessful for PUT #{path} : #{status_code} #{err_msg}"}
        end
      rescue PersistentHTTP::Error => err
        logger.error{"[FF] Request failed for PUT #{path} : #{err.message}"}
      rescue Exception => err
        logger.error{"[FF] Request failed for PUT #{path} : #{err.message}"}
        raise
      end

      log_api_request("PUT", url_path, duration, status_code, err_msg)
      return success
    end

    def post(path, auth_token, payload)
      uri = URI(@base_uri + path)
      url_path = uri.path
      duration = nil
      status_code = nil
      err_msg = nil
      success = false
      begin
        request = Net::HTTP::Post.new url_path
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request['AUTHORIZATION'] = auth_token
        request.body = JSON.dump(payload)

        request_start_time = Time.now
        response = @http.request request
        duration = Time.now - request_start_time

        raise "expected Net::HTTPResponse" if not response.is_a? Net::HTTPResponse
        status_code = response.code
        if response.is_a? Net::HTTPSuccess
          success = true
        else
          response_payload = JSON.load(response.body) rescue nil
          if response_payload.is_a? Hash and response_payload.has_key? "error"
            err_msg = response_payload["error"]
          end
          logger.error{"[FF] Request unsuccessful for POST #{path} : #{status_code} #{err_msg}"}
        end
      rescue PersistentHTTP::Error => err
        logger.error{"[FF] Request failed for POST #{path} : #{err.message}"}
      rescue Exception => err
        logger.error{"[FF] Request failed for POST #{path} : #{err.message}"}
        raise
      end

      log_api_request("POST", url_path, duration, status_code, err_msg)
      return success
    end

  end
end
