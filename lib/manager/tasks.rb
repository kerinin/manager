class Manager
  class Tasks
    extend Assembler

    assemble_from(
      :config,
      :coordinator,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def cycle
      active, inactive = tasks.values.partition(&:started?)

      if active.count == config.max_active_partitions
        logger.info(log_progname) { "Cycling active tasks" }

        active.first.terminate unless active.empty?
        inactive.first.start unless inactive.empty?
        tasks.merge!(Hash[[tasks.shift]]) # janky hash rotation

      elsif !inactive.empty?
        loop do
          if active.count < config.max_active_partitions
            logger.debug(log_progname) { "Starting tasks" }

            if inactive.empty?
              break
            else
              inactive.first.start
            end

          elsif active.count > config.max_active_partitions
            logger.debug(log_progname) { "Terminating tasks" }

            if active.empty?
              break
            else
              active.first.terminate
            end
          else
            break
          end

          sleep 1
          active, inactive = tasks.values.partition(&:started?)
        end
      end
    end

    def schedule(partition)
      unless tasks.has_key?(partition.id)
        logger.info(log_progname) { "Scheduling task for partition '#{partition.id}'" }

        tasks[partition.id] = Task.new do |b|
          b.partition = partition
          b.config = config
          b.logger = logger
        end

        if tasks.values.select(&:started?).count < config.max_active_partitions
          cycle
        end
      end
    end

    def stop_scheduling(partition_id)
      if tasks.has_key?(partition_id)
        logger.info(log_progname) { "Stopping scheduling for partition '#{partition_id}'" }

        if task = tasks.delete(partition_id)
          task.terminate if task.started?
        end
      end
    end

    def terminate_all
      logger.debug(log_progname) { "Terminating all tasks" }

      tasks.values.select(&:started?).each { |task| task.terminate }
    end

    def scheduled_partitions
      tasks.keys
    end

    private

    def tasks
      @tasks ||= {}
    end
  end
end
