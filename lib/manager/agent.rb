class Manager
  class Agent
    class CASException < StandardError; end

    extend Assembler
    
    assemble_from(
      :consul_servers,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
      agent_options: {},
    )

    def start
      default_options = {data_dir: './'}
      options = default_options.
        merge(agent_options).
        map { |k,v| "-#{k.to_s.gsub('_','-')}=#{v}" }.join(' ')

      logger.info(log_progname) { "Starting agent with options '#{options}'" }

      pid = Process.fork
      if pid.nil?
        exec "consul agent #{options} > /dev/null 2>&1"
      end
    end

    def join
      consul_server = consul_servers.shuffle.first

      logger.info(log_progname) { "Joining Consul server cluster at '#{consul_server}'" }

      Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/join/#{consul_server}"

        yield b if block_given?
      end.response

      return true
    end

    def register_service(service)
    end

    def get_key(key, options={})
      logger.info(log_progname) { "Requesting key '#{key}' with options '#{options}'" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response

      return JSON.parse(res.body) if res.body
    end

    def put_key(key, value, options={})
      logger.info(log_progname) { "Setting key '#{key}'='#{value}' with options '#{options}'" }

      res = Request.new do |b|
        b.verb = :put
        b.path = "/v1/kv/#{key}"
        b.queryargs = options
        b.body = value

        yield b if block_given?
      end.response

      raise CASException if res.body == 'false'

      return true
    end

    def delete_key(key, options={})
      logger.info(log_progname) { "Deleting key '#{key}' with options '#{options}'" }

      Request.new do |b|
        b.verb = :delete
        b.path = "/v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response
      return true
    end

    def get_service_health(service_id)
      logger.info(log_progname) { "Getting health status for service '#{service_id}'" }

      res = Request.new do |b|
        b.verb = :get
        b.path = "v1/health/service/#{service_id}"
        b.queryargs = options

        yield b if block_given?
      end.response

      return JSON.parse(res.body) if res.body
    end

    def register_check(check)
      logger.info(log_progname) { "Registering check '#{check}'" }

      Request.new do |b|
        b.verb = :put
        b.path = "/v1/agent/check/register"
        b.body = check

        yield b if block_given?
      end.response

      return true
    end

    def force_leave(node)
      logger.info(log_progname) { "Forcing node '#{node}' to leave the Consul cluster" }

      Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/force-leave/#{node}"

        yield b if block_given?
      end.response

      return true
    end

    def leave
      logger.info(log_progname) { "Leaving the Consul cluster" }

      `consul leave`
    end

    class Request
      extend Assembler

      assemble_from(
        :verb,
        :path,
        queryargs: {},
        body: nil,

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
        end
      end

      private

      def url_for(path, options={})
        "#{path}?#{options.map {|k,v| "#{k}=#{v}"}.join("&")}"
      end

      def connection
        @connection ||= Faraday.new(url: 'http://localhost') do |f|
          f.adapter   Faraday.default_adapter
          f.use       FaradayMiddleware::EncodeJson
          f.use       Faraday::Response::RaiseError
        end
      end
    end
  end
end
