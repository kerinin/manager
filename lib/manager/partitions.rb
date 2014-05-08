class Manager
  class Partitions
    extend Assembler
    include Enumerable

    module LinearPartitioner
      def self.call(partitions, nodes)
        Hash[partitions.map.with_index { |key, i| [key, nodes[i % nodes.length] ] }]
      end
    end

    module ConsistentHashPartitioner
      def self.call(partitions, nodes)
        ring = ConsistentHashing::Ring.new
        ring.add(nodes)
        Hash[partitions.map { |key| [key, ring.node_for(key).first] }]
      end
    end

    assemble_from(
      :agent,
      :service_id,
      :partition_key,
      logger: Logger.new(STDOUT),
      partitioner: ConsistentHashPartitioner,
      log_progname: self.name,
    )

    def each(&block)
      partition_assignments.each do |partition_key, node_id|
        partition = Partition.new(
          service_id: service_id,
          agent: agent,
          partition_key: partition_key,
          assigned_to: node_id,
          logger: logger,
        )
        block.call partition
      end
    end

    def save(partition_set)
      logger.info(log_progname) { "Saving partition set '#{partition_set}'" }

      agent.put_key(partition_key, partition_set)
    end

    private

    def partition_assignments
      partitioner.call(partition_keys, nodes)
    end

    def partition_keys
      @partition_set ||= agent.get_key(partition_key)
    end

    def nodes
      @nodes ||= agent.
        get_service_health(service_id).
        select { |h| h["Checks"].all? { |c| c["Status"] == "passing" } }.
        map { |h| h["Node"]["Node"] }
    end
  end
end
