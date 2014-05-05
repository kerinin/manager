class Manager
  class Partition
    extend Assembler

    assemble_from(
      :agent,
      :key,
      :assigned_to,
    )
    attr_reader :assigned_to

    def assigned_to?(node)
      assigned_to == node
    end

    def acquired_by
      Base64.decode64(remote_value["Value"])
    end

    def acquired_by?(node)
      acquired_by == node
    end

    def acquire
      if acquired_by
        raise StandardError, "Tried to acquire an already-acquired partition"
      else
        agent.set_key(key, value) do |b|
          b.queryargs = {cas: remote_value["ModifyIndex"]}
        end
      end
    end

    def release
      agent.set_key(key, nil)
    end

    private

    def remote_value
      @remote_value = agent.get_key(key)
    end
  end
end
