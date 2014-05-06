class Manager
  class Coordinator
    def add_listener(endpoint, &block)
      threads << Thread.new {
        Listener.new(endpoint: endpoint).each do |json|
          work_queue << [block, json]
        end
      }
    end

    def run
      loop do
        if value = work_queue.pop
          value.first.call value.rest
        else
          sleep 1
        end
      end
    end

    private

    def threads
      @threads ||= []
    end

    def work_queue
      @work_queue ||= Queue.new
    end

    class Listener
      extend Assembler

      assemble_from(
        :endpoint,
        timout: '10m',
      )

      def each(&block)
        cached = nil
        index = nil
        loop do
          current, index = do_request(index)

          if current != cached
            cached = current
            block.call(current)
          end
        end
      end

      private

      def do_request(index=nil)
        response = if index
                     client.get("#{endpoint}?wait=#{timeout}&index=#{index}")
                   else
                     client.get(endpoint)
                   end

        case response.status.to_s
        when /2../
          return response.body, response.headers["X-Consul-Index"]
        else
          raise StandardError, 'HTTP Failure'
        end
      end
    end
  end
end
