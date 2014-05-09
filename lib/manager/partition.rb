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
    class IllegalModificationException < StandardError; end

    extend Assembler

    assemble_from(
      :service_id,
      :agent,
      :partition_key,
      :assigned_to,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )
    attr_reader :assigned_to, :partition_key

    def consul_path
      "/v1/kv/#{service_id}/partition/#{partition_key}"
    end

    def assigned_to?(node)
      assigned_to.to_s == node.to_s
    end

    def acquired_by
      remote_value.value
    end

    def acquired_by?(node)
      acquired_by.to_s == node.to_s
    end

    def acquire
      logger.info(log_progname) { "Attempting to acquire partition #{partition_key}" }

      if acquired_by?(service_id)
        return true
      elsif acquired_by
        raise IllegalModificationException, "Tried to acquire partition #{partition_key}, but it's already assigned to #{acquired_by}"
      else
        agent.put_key(partition_key, service_id) do |b|
          b.queryargs = {cas: remote_value["ModifyIndex"]}
        end
      end
    end

    def release
      logger.info(log_progname) { "Attempting to release partition #{partition_key}" }

      if !acquired_by
        return true
      elsif !acquired_by?(service_id)
        raise IllegalModificationException, "Tried to release partition #{partition_key}, but it's assigned to #{acquired_by}"
      else
        agent.set_key(partition_key, nil) do |b|
          b.queryargs = {cas: remote_value["ModifyIndex"]}
        end
      end
    end

    private

    def remote_value
      @remote_value = agent.get_key(partition_key)
    end
  end
end
