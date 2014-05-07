class Manager
  class Coordinator
    extend Assembler

    assemble_from(
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def add_listener(endpoint, &block)
      logger.info(log_progname) { "Adding listener on '#{endpoint}'" }

      threads << Thread.new {
        Listener.new(endpoint: endpoint).each do |json|
          work_queue << [block, json]
        end
      }
    end

    def run
      logger.info(log_progname) { "Starting the work loop" }

      loop do
        drain_work_queue
        sleep 1
      end
    end

    def drain_work_queue
      logger.info(log_progname) { "Draining the work queue" }

      loop do
        value = work_queue.pop(true)
        value.first.call(*value[1..-1])
      end
    rescue ThreadError
      unless $!.message.match /queue empty/
        raise
      end
    end

    def kill
      logger.info(log_progname) { "Killing managed threads" }

      threads.each(&:kill)
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
        timeout: '10m',
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
                     connection.get("#{endpoint}?wait=#{timeout}&index=#{index}")
                   else
                     connection.get(endpoint)
                   end

        return JSON.parse(response.body), response.headers["X-Consul-Index"]
      end

      def connection
        @connection ||= Faraday.new(url: 'http://localhost') do |f|
          f.adapter   Faraday.default_adapter
          f.use       Faraday::Response::RaiseError
        end
      end
    end
  end
end
