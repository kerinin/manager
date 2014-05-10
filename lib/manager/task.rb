class Manager
  class Task
    extend Assembler

    assemble_from(
      :partition,
      :config,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def start
      logger.info(log_progname) { "Starting task for partition '#{partition.id}'" }

      if config.on_acquiring_partition_block
        config.on_acquiring_partition_block.call partition.id
      end
    end

    def terminate
      logger.info(log_progname) { "Terminating task for partition '#{partition.id}'" }

      if config.on_releasing_partition_block
        config.on_releasing_partition_block.call partition.id
      end
    end
  end
end
