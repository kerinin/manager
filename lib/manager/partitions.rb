class Manager
  class Partitions
    extend Assembler
    include Enumerable

    assemble_from(
      :agent,
      :service,
      :partition_key,
      partition_set: nil
    )

    def each(&block)
      partition_assignments.each do |partition_key, node_ip|
        block.call Partition.new(agent: agent, key: partition_key, assigned_to: node_ip)
      end
    end

    def save(set)
      agent.set_key(partition_key, set)
    end

    private

    def partition_assignments
      ring = ConsistentHashing::Ring.new
      ring.add(nodes)
      Hash[partition_keys.map { |key| [key, ring.node_for(key)] }]
    end

    def partition_keys
      @partition_set ||= agent.get_key(partition_key)
    end

    def nodes
      @nodes ||= agent.get_service(service).map { |h| h["Address"] }
    end
  end
end
