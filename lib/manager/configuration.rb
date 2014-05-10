class Manager
  class Configuration
    attr_writer :node, :service_id
    attr_accessor :service_name
    attr_reader :on_acquiring_partition_block, :on_releasing_partition_block

    def node
      @node || `hostname`.chomp
    end

    def service_id
      @service_id || service_name
    end

    def tags
      @tags ||= []
    end

    def partitions
      @partitions ||= []
    end

    def on_acquiring_partition(&block)
      @on_acquiring_partition_block = block
    end

    def on_releasing_partition(&block)
      @on_releasing_partition_block = block
    end

    # def health_checks
    #   @health_checks ||= {}
    # end

    # def health_check_script(name, &block)
    #   @script_health_checks ||= []
    #   check = ScriptHealthCheck.new(name, &block)
    #   health_checks[check.id] = check
    # end

    # def health_check_ttl(name, &block)
    #   @ttl_health_checks ||= []
    #   check = TTLHealthCheck.new(name, &block)
    #   health_checks[check.id] = check
    # end


    def service_definition
      {
        ID: service_id,
        Name: service_name,
        Tags: service_tags,
        Port: service_port,
      }
    end

    def validate!
      raise ArgumentError, 'Service Name missing' unless service_name
    end
  end
end
