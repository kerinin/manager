class Manager
  # The Partition class manages partition assignement in the Consul KV store
  # and exposes methods describing partition assignment and acquisition.
  #
  # This class is intended to be a short-lived snapshot of the remote state of
  # the Consul store.  The remote value is requested once and memoized.  
  #
  # If you're instantiating these directly, you're probably doing something
  # wrong - these should generally be constructed by a Partitions instance,
  # which knows how to compute partition assignments.
  #
  class Partition
    extend Assembler

    assemble_from(
      :service_id,
      :agent,
      :partition_key,
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
