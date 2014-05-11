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
        partition_key = "#{config.service_id}/p_#{id}"
        if consul_kv_data.has_key?(partition_key)
          remote_value = consul_kv_data[partition_key]
        else
          remote_value = OpenStruct.new(
            value: nil,
            create_index: nil,
            modify_index: 0,
            flags: [],
          )
        end

        partition = Partition.new(
          id: id,
          agent: agent,
          config: config,
          assigned_to: node_id,
          remote_value: remote_value,
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

    def consul_kv_data
      @consul_kv_data ||= agent.get_keys(config.service_id)
    end

    def partitions_key
      "#{config.service_id}/partitions"
    end

    # The set of partitions to be allocated
    def partition_ids
      consul_kv_data[partitions_key].value
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
