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
        nodes.each { |node| ring.add(node) }
        Hash[partitions.map { |key| [key, ring.node_for(key)] }]
      end
    end

    assemble_from(
      :agent,
      :config,
      logger: Logger.new(STDOUT),
      # partitioner: ConsistentHashPartitioner,
      partitioner: LinearPartitioner,
      log_progname: self.name,
    )

    def each(&block)
      partition_assignments.each do |id, node_id|
        partition = Partition.new(
          id: id,
          agent: agent,
          config: config,
          assigned_to: node_id,
          logger: logger,
        )
        block.call partition
      end
    end

    def save(partition_set)
      logger.debug(log_progname) { "Saving partition set '#{partition_set}'" }

      agent.put_key(partitions_key, partition_set)
    end

    private

    # The Consul key name where the set of partitions is stored
    def partitions_key
      @partitions_key ||= [config.service_id, :partitions].join('/')
    end

    # The set of partitions to be allocated
    def partition_ids
      @partition_ids ||= agent.get_key(partitions_key).value
    end

    def partition_assignments
      return {} if partition_ids.empty? || nodes.empty?

      partitioner.call(partition_ids, nodes)
    end

    def nodes
      @nodes ||= agent.
        get_service_health(config.service_id).
        select { |h| h["Checks"].all? { |c| c["Status"] == "passing" } }.
        map { |h| h["Node"]["Node"] }
    end
  end
end
