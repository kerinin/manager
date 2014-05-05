class Manager
  class Agent
    extend Assembler
    
    assemble_from(
      :consul_servers,
      agent_options: {},
    )

    def begin
      options = agent_options.map { |k,v| "-#{k.to_s.gsub('_','-')}=#{v}" }.join(' ')

      `consul agent #{options}`
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

        yield b in block_given?
      end.response

      return res.body
    end

    def put_key(key, value, options={})
      res = Request.new do |b|
        b.verb = :put
        b.path = "/v1/kv/#{key}"
        b.queryargs = options
        b.body = value

        yield b in block_given?
      end.response

      raise CASException if response.body == 'false'

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
        response = connection.send(verb, url_for(path, queryargs))

        case response.status.to_s
        when /2../
          return response
        else
          raise StandardError, 'HTTP fucked, too lazy to write explicit error classes'
        end
      end

      private

      def url_for(path, options={})
        "#{path}?#{options.map {|k,v| "#{k}=#{v}"}.join("&")}"
      end
    end
  end
end
