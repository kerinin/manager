class Manager
  class Coordinator
    extend Assembler

    assemble_from(
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def listening_to?(endpoint)
      threads.has_key?(endpoint)
    end

    def add_listener(endpoint, &block)
      logger.debug(log_progname) { "Adding listener on '#{endpoint}'" }

      threads[endpoint] = Thread.new {
        Listener.new(endpoint: endpoint, logger: logger).each do |json|
          work_queue << [block, json]
        end
      }
    end

    def remove_listener(endpoint)
      logger.debug(log_progname) { "Removing listener from '#{endpoint}'" }

      listener = threads.delete(endpoint)
      listener.kill if listener
    end

    def run
      logger.debug(log_progname) { "Starting the work loop" }

      loop do
        drain_work_queue
        sleep 1
      end
    ensure
      kill
    end

    def drain_work_queue
      logger.debug(log_progname) { "Draining the work queue" }

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
      logger.debug(log_progname) { "Killing managed threads" }

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
        :logger,
        timeout: 600, # 10 minutes
        log_progname: self.name,
      )

      def each(&block)
        last_value = nil
        last_index = nil

        loop do
          value, index = do_request(last_index)

          if index.nil?
            # For endpoints that don't support blocking reads
            if value != last_value
              last_value = value
              block.call(value)
            end
            sleep 60

          elsif index != last_index
            # For endpoints that do
            last_index = index
            block.call(value)
          end
        end
      end

      private

      def do_request(index=nil)
        if index.nil?
          logger.debug(log_progname) { "GET #{endpoint}" }

          res = connection.get(endpoint)
        else
          request_endpoint = "#{endpoint}?wait=#{timeout}s&index=#{index}"

          logger.debug(log_progname) { "GET #{request_endpoint}" }

          res = connection.get(
            request_endpoint,
            timeout: timeout + 60,
          )
        end

        case res.status.to_s
        when /2../
          return JSON.parse(res.body), res.headers["X-Consul-Index"]
        when /404/
          return nil, res.headers["X-Consul-Index"]
        else
          raise StandardError, "WTF? #{endpoint} #{res.status} #{res.headers}, #{res.body}"
        end
      rescue Faraday::Error::TimeoutError
        retry
      end

      def connection
        @connection ||= Faraday.new(url: 'http://127.0.0.1:8500') do |f|
          f.adapter   Faraday.default_adapter
        end
      end
    end
  end
end
