class Manager
  class PartitionRebalancer
    extend Assembler

    assemble_from(
      :rebalancer,
      :config,
      :partition,
      :tasks,
      :coordinator,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def call
      if partition.assigned_to?(config.node)
        if partition.acquired_by?(config.node)
          logger.debug(log_progname) { "Partition '#{partition.id}' already acquired" }

          start_task_for_partition
        elsif !partition.acquired_by
          logger.debug(log_progname) { "Acquiring partition '#{partition.id}'" }

          acquire_partition
        else
          logger.debug(log_progname) { "Waiting for partition '#{partition.id}' to become available" }

          wait_for_partition
        end
      else
        if partition.acquired_by?(config.node)
          logger.debug(log_progname) { "Releasing partition '#{partition.id}' to '#{partition.assigned_to}' (I'm #{config.node})" }

          release_partition
        else
          logger.debug(log_progname) { "Partition '#{partition.id}' assigned to '#{partition.assigned_to}' (I'm #{config.node})" }

          terminate_task_for_partition
        end
      end
    end

    private

    def start_task_for_partition
      tasks.schedule(partition)
    end

    def acquire_partition
      coordinator.remove_listener(partition.consul_path)
      partition.acquire
      tasks.schedule(partition)
    end

    def wait_for_partition
      unless coordinator.listening_to?(partition.consul_path) 
        coordinator.add_listener(partition.consul_path) do
          logger.info(log_progname) { "Value of partition '#{partition.id}' changed" }

          rebalancer.rebalance
        end
      end
    end

    def release_partition
      coordinator.remove_listener(partition.consul_path)
      tasks.stop_scheduling(partition.id)
      partition.release
    end

    def terminate_task_for_partition
      tasks.stop_scheduling(partition.id)
    end
  end
end
