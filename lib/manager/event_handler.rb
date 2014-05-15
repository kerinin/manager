class Manager
  class EventHandler
    extend Assembler

    assemble_from(
      :config,
      :coordinator,
      logger: Logger.new(STDOUT),
      log_progname: self.name,
    )

    def on_instance_set_changes
      coordinator.add_listener("/v1/catalog/service/#{config.service_id}") { |json|
        raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

        logger.info(log_progname) { "Cluster membership changed" }

        yield json if block_given?
      }
    end

    def on_partition_set_changes
      coordinator.add_listener("/v1/kv/#{config.service_id}/partitions") { |json|
        raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

        yield json if block_given?
      }
    end

    def on_node_failure
      coordinator.add_listener("/v1/health/service/#{config.service_id}") { |json|
        raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

        logger.info(log_progname) { "Cluster health changed" }

        failing_nodes = json.select do |node|
          node["Checks"].any? { |check| check["CheckID"] == "serfHealth" && check["Status"] == "critical" }
        end.map { |node| node["Node"]["Node"] }

        unless failing_nodes.empty?
          logger.info(log_progname) { "Detected #{failing_nodes.count} failed nodes: #{failing_nodes}" }

          failing_nodes.each do |node|
            yield node if block_given?
          end
        end
      }
    end
  end
end
