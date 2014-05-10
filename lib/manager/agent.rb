class Manager
  class Agent
    class HTTPRedirectException < StandardError; end
    class HTTPClientError < StandardError; end
    class HTTPServerError < StandardError; end
    class CASException < StandardError; end

    extend Assembler
    
    assemble_from(
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def start(agent_options={})
      default_options = {data_dir: './'}
      options = default_options.
        merge(agent_options).
        map { |k,v| ["-#{k.to_s.gsub('_','-')}", v] }.
        map { |k,v| [true,false].include?(v) ? k : "#{k}=#{v}"  }.
        join(' ')
      # command = "consul agent #{options} > /dev/null 2>&1"
      command = "consul agent #{options}"

      logger.info(log_progname) { "Starting agent with `#{command}`" }

      pid = Process.fork
      if pid.nil?
        exec command
      else
        begin
          res = Request.new(verb: :get, path: '/v1/catalog/services').response
          sleep 1
        rescue Faraday::Error::ConnectionFailed
          sleep 1
          retry
        end
      end
    end

    def join(consul_server)
      logger.info(log_progname) { "Joining Consul server cluster at '#{consul_server}'" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/join/#{consul_server}"

        yield b if block_given?
      end.response

      handle_response(res)
    end

    def register_service(service_definition)
      logger.info(log_progname) { "Regestering service '#{service_definition[:Name]}'" }

      res = Request.new do |b|
        b.verb = :put
        b.path = "/v1/agent/service/register"
        b.content_type = "application/json"
        b.body = JSON.dump(service_definition)

        yield b if block_given?
      end.response

      handle_response(res)
    end

    def get_key(key, options={})
      logger.info(log_progname) { "Requesting key '#{key}' with options '#{options}'" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response

      handle_response(res) do |h|
        h.status /2../ do
          value = JSON.parse(res.body).select { |json| json["Key"] == key.to_s }.map do |json|
            OpenStruct.new(
              value: YAML.load(Base64.decode64(json["Value"])),
              create_index: json["CreateIndex"],
              modify_index: json["ModifyIndex"],
              flags: json["Flags"],
            )
          end.first

          logger.info(log_progname) { "Key '#{key}' returned value '#{value}'" }

          value
        end

        h.status /404/ do
          OpenStruct.new(
            value: nil,
            create_index: nil,
            modify_index: res.headers['X-Consul-Index'],
            flags: [],
          )
        end
      end
    end

    def put_key(key, value, options={})
      logger.info(log_progname) { "Setting key '#{key}'='#{value}' with options '#{options}'" }

      res = Request.new do |b|
        b.verb = :put
        b.path = "/v1/kv/#{key}"
        b.queryargs = options
        b.content_type = 'text/yaml'

        # This is being recorded as having surrounding quotation marks...
        b.body = YAML.dump(value)

        yield b if block_given?
      end.response

      handle_response(res) do |h|
        h.status /2../ do
          raise CASException if res.body == 'false'
          true
        end
      end
    end

    def delete_key(key, options={})
      logger.info(log_progname) { "Deleting key '#{key}' with options '#{options}'" }

      res = Request.new do |b|
        b.verb = :delete
        b.path = "/v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response

      handle_response(res)
    end

    def get_service_health(service_id, options={})
      logger.info(log_progname) { "Getting health status for service '#{service_id}'" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "v1/health/service/#{service_id}"
        b.queryargs = options

        yield b if block_given?
      end.response

      handle_response(res) do |h|
        h.status /2../ do
          JSON.parse(res.body) if res.body
        end
      end
    end

    def register_check(check)
      logger.info(log_progname) { "Registering check '#{check}'" }

      res = Request.new do |b|
        b.verb = :put
        b.path = "/v1/agent/check/register"
        b.body = JSON.dump(check)

        yield b if block_given?
      end.response

      handle_response(res)
    end

    def force_leave(node)
      logger.info(log_progname) { "Forcing node '#{node}' to leave the Consul cluster" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/force-leave/#{node}"

        yield b if block_given?
      end.response

      handle_response(res)
    end

    def leave
      logger.info(log_progname) { "Leaving the Consul cluster" }

      `consul leave`
    end

    private

    def handle_response(response)
      if block_given?
        dsl = HandlerDSL.new
        yield dsl

        dsl.handlers.each do |regex, block|
          if response.status.to_s =~ regex
            return block.call
          end
        end
      end

      case response.status.to_s
      when /2../
        return true
      when /3../
        raise HTTPRedirectException, "Response redirected: #{response.headers}"
      when /4../
        raise HTTPClientError, "Client Error: #{response.body}"
      when /5../
        raise HTTPServerError, "Server Error: #{response.body}"
      end
    end

    class HandlerDSL
      def handlers
        @handlers ||= {}
      end

      def status(regex, &block)
        handlers[regex] = block
      end
    end

    class Request
      extend Assembler

      assemble_from(
        :verb,
        :path,
        queryargs: {},
        body: nil,
        content_type: nil,

        # Blocking queries
        wait: nil,
        index: nil,

        # default/consistent/stale
        consistency_mode: :default,
        stale_last_contact: nil,
        stale_known_leader: nil,
      )

      def response
        connection.send(verb, url_for(path, queryargs)) do |req|
          req.body = body if body
          req.headers['Content-Type'] = content_type if content_type
        end
      end

      private

      def url_for(path, options={})
        if options.empty?
          path
        else
          "#{path}?#{options.map {|k,v| "#{k}=#{v}"}.join("&")}"
        end
      end

      def connection
        @connection ||= Faraday.new(url: 'http://127.0.0.1:8500') do |f|
          f.adapter   Faraday.default_adapter
          # f.use       FaradayMiddleware::EncodeJson
          # f.use       Faraday::Response::RaiseError
        end
      end
    end
  end
end
