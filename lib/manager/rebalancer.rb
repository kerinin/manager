class Manager
  class Rebalancer
    extend Assembler

    assemble_from(
      :config,
      :partitions,
      :tasks,
      :coordinator,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def rebalance
      logger.info(log_progname) { "Rebalancing" }

      partitions.each do |partition|
        PartitionRebalancer.new(
          rebalancer: self,
          config: config,
          partition: partition,
          tasks: tasks,
          coordinator: coordinator,
          logger: logger,
        ).call
      end

      (tasks.scheduled_partitions - partitions.map(&:id)).each do |removed_partition_id|
        tasks.stop_scheduling(removed_partition_id)
      end
    end
  end
end
