class Manager
  class Agent
    class CASException < StandardError; end

    extend Assembler
    
    assemble_from(
      :consul_servers,
      agent_options: {},
    )

    def start
      default_options = {data_dir: './'}
      options = default_options.
        merge(agent_options).
        map { |k,v| "-#{k.to_s.gsub('_','-')}=#{v}" }.join(' ')

      pid = Process.fork
      if pid.nil?
        exec "consul agent #{options} > /dev/null 2>&1"
      end
    end

    def join
      Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/join/#{consul_servers.shuffle.first}"

        yield b if block_given?
      end.response

      return true
    end

    def get_key(key, options={})
      res = Request.new do |b|
        b.verb = :get
        b.path = "v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response

      return JSON.parse(res.body) if res.body
    end

    def put_key(key, value, options={})
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
      Request.new do |b|
        b.verb = :delete
        b.path = "/v1/kv/#{key}"
        b.queryargs = options

        yield b if block_given?
      end.response
      return true
    end

    def register_check(check)
      Request.new do |b|
        b.verb = :put
        b.path = "/v1/agent/check/register"
        b.body = check

        yield b if block_given?
      end.response

      return true
    end

    def force_leave(node)
      Request.new do |b|
        b.verb = :get
        b.path = "/v1/agent/force-leave/#{node}"

        yield b if block_given?
      end.response

      return true
    end

    def leave
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
