class Manager
  class Task
    extend Assembler

    assemble_from(
      :partition,
      :on_start,
      :on_terminate,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def start
      logger.info(log_progname) { "Starting task for partition '#{partition}'" }

      on_start.call partition.partition_key
    end

    def terminate
      logger.info(log_progname) { "Terminating task for partition '#{partition}'" }

      on_terminate.call partition.partition_key
    end
  end
end
