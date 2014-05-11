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
      :id,
      :agent,
      :config,
      :assigned_to,
      :remote_value,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )
    attr_reader :assigned_to, :id

    def consul_path
      "http://localhost:8500/v1/kv/#{partition_key}"
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
      logger.debug(log_progname) { "Attempting to acquire partition #{id}" }

      if acquired_by?(config.node)
        return true
      elsif acquired_by
        raise IllegalModificationException, "Tried to acquire partition #{id}, but it's already assigned to #{acquired_by}"
      else
        agent.put_key(partition_key, config.node, cas: remote_value.modify_index)
      end
    end

    def release(force = false)
      logger.debug(log_progname) { "Attempting to release partition #{id}" }

      if !acquired_by
        return true
      elsif !acquired_by?(config.node) && !force
        logger.warn(log_progname) { "Tried to release partition #{id}, but it's assigned to #{acquired_by}" }
      else
        agent.put_key(partition_key, nil, cas: remote_value.modify_index)
      end
    end

    private

    def partition_key
      @paritition_key ||= "#{config.service_id}/p_#{id}"
    end
  end
end
