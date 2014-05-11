require 'assembler'
require 'base64'
require 'manager/version'
require 'consistent_hashing'
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'logger'
require 'ostruct'
require 'pry'
require 'yaml'

Thread.abort_on_exception = true

class Manager
  def self.pids
    @pids ||= {}
  end

  def self.exec(name, script)
    pid = Process.fork
    if pid.nil?
      exec script
    else
      pids[name] = pid
    end
  end

  def initialize(options = {})
    @logger = options[:logger] || Logger.new(STDOUT)
    # @logger.level = Logger::INFO
    @logger.level = Logger::DEBUG
    @config = Configuration.new

    yield @config

    @config.validate!
  end

  def run
    agent.register_service(config.service_definition)

    listeners = []

    partitions.save(config.partitions)

    # Listen for changes to instance set
    coordinator.add_listener("/v1/catalog/service/#{config.service_id}") { |json|
      raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

      logger.info(log_progname) { "Cluster membership changed" }

      rebalance
    }

    # Listen for changes to partition set
    # coordinator.add_listener("/v1/kv/#{config.service_id}/partitions") { |json|
    #   raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

    #   rebalance
    # }

    # Listen for disconnected instances
    coordinator.add_listener("/v1/health/service/#{config.service_id}") { |json|
      raise "Unexpected json: #{json}" unless json.kind_of?(Enumerable)

      logger.info(log_progname) { "Cluster health changed" }

      failing_nodes = json.select do |node|
        node["Checks"].any? { |check| check["CheckID"] == "serfHealth" && check["Status"] == "critical" }
      end.map { |node| node["Node"]["Node"] }

      unless failing_nodes.empty?
        logger.info(log_progname) { "Detected #{failing_nodes.count} failed nodes: #{failing_nodes}" }

        failed_partitions = partitions.select do |partition|
          failing_nodes.include?(partition.acquired_by)
        end
        failed_partitions.each { |p| p.release(true) }
        logger.debug(log_progname) { "Force-released node's #{failed_partitions.count} partitions: #{failed_partitions.map(&:id)}" }

        failing_nodes.each do |node|
          agent.force_leave(node)
        end
        logger.debug(log_progname) { "Forced failed nodes to leave the cluster" }

        rebalance
      end
    }

    coordinator.run

  ensure
    tasks.map { |partition, task| task.terminate }
    partitions.select { |p| p.acquired_by?(config.node) }.each(&:release)
    agent.deregister_service(config.service_id)
  end

  def agent
    @agent ||= Agent.new do |b|
      b.logger = logger
    end
  end

  private

  attr_accessor :config, :logger

  def log_progname
    self.class.name
  end

  def rebalance
    logger.info(log_progname) { "Rebalancing" }

    partition_snapshot = partitions

    partition_snapshot.each do |partition|
      if partition.assigned_to?(config.node)
        if partition.acquired_by?(config.node)
          logger.debug(log_progname) { "Partition '#{partition.id}' already acquired" }

          tasks[partition.id] ||= Task.new do |b|
            b.partition = partition
            b.config = config
            b.logger = logger
          end
          tasks[partition.id].start unless tasks[partition.id].started?
          
        elsif !partition.acquired_by
          logger.debug(log_progname) { "Acquiring partition '#{partition.id}'" }

          coordinator.remove_listener(partition.consul_path)
          partition.acquire

          tasks[partition.id] ||= Task.new do |b|
            b.partition = partition
            b.config = config
            b.logger = logger
          end
          tasks[partition.id].start

        else
          logger.debug(log_progname) { "Waiting for partition '#{partition.id}' to become available" }

          unless coordinator.listening_to?(partition.consul_path) 
            coordinator.add_listener(partition.consul_path) do
              logger.info(log_progname) { "Value of partition '#{partition.id}' changed" }

              rebalance
            end
          end
        end
      else
        if partition.acquired_by?(config.node)
          logger.debug(log_progname) { "Releasing partition '#{partition.id}' to '#{partition.assigned_to}' (I'm #{config.node})" }

          coordinator.remove_listener(partition.consul_path)
          tasks[partition.id].terminate if tasks.has_key?(partition.id)
          partition.release
        else
          logger.debug(log_progname) { "Partition '#{partition.id}' assigned to '#{partition.assigned_to}' (I'm #{config.node})" }

          tasks[partition.id].terminate if tasks.has_key?(partition.id) && tasks[partition.id].started?
        end
      end
    end

    tasks.each do |partition_id, task|
      task.terminate unless partition_snapshot.map(&:id).include?(partition_id)
    end
  end

  def partitions
    Partitions.new do |b|
      b.agent = agent
      b.config = config
      b.logger = logger
    end
  end

  def tasks
    @tasks ||= {}
  end

  def coordinator
    @coordinator ||= Coordinator.new(logger: logger)
  end
end

require 'manager/agent'
require 'manager/coordinator'
require 'manager/configuration'
require 'manager/partition'
require 'manager/partitions'
require 'manager/task'
