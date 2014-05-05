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
  end
end
