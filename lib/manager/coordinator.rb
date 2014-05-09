class Manager
  class Coordinator
    extend Assembler

    assemble_from(
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def add_listener(endpoint, &block)
      logger.info(log_progname) { "Adding listener on '#{endpoint}'" }

      threads[endpoint] = Thread.new {
        Listener.new(endpoint: endpoint).each do |json|
          work_queue << [block, json]
        end
      }
    end

    def remove_listener(endpoint)
      logger.info(log_progname) { "Removing listener from '#{endpoint}'" }

      listener = threads.delete(endpoint)
      listener.kill if listener
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

      threads.keys.each { |k| remove_listener(k) }
    end

    private

    def threads
      @threads ||= {}
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

          # For endpoints that don't support blocking reads, just sleep for a 
          # minute and then poll again
          if index.nil?
            sleep 60
          end
        end
      end

      private

      def do_request(index=nil)
        response = if index
                     Logger.new(STDOUT).info("Requesting GET #{endpoint}?wait=#{timeout}&index=#{index}")
                     connection.get("#{endpoint}?wait=#{timeout}&index=#{index}")
                   else
                     Logger.new(STDOUT).info("Requesting GET #{endpoint}")
                     connection.get(endpoint)
                   end

        return JSON.parse(response.body), response.headers["X-Consul-Index"]
      rescue
        Logger.new(STDOUT).warn("Failed to GET #{endpoint}")
      end

      def connection
        @connection ||= Faraday.new(url: 'http://127.0.0.1:8500') do |f|
          f.adapter   Faraday.default_adapter
          f.use       Faraday::Response::RaiseError
        end
      end
    end
  end
end
