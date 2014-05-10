require 'assembler'
require 'base64'
require 'manager/version'
require 'consistent_hashing'
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'logger'
require 'ostruct'
require 'yaml'

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
    @config = Configuration.new

    yield @config

    @config.validate!
  end

  def run
    validate!
    agent.register_service(config.service_definition)

    listeners = []

    partitions.save(config.partitions)

    # Listen for changes to instance set
    coordinator.add_listener("/v1/catalog/service/#{config.service_id}") { |json|
      rebalance
    }

    # Listen for changes to partition set
    coordinator.add_listener("/v1/kv/#{config.service_id}/partitions") { |json|
      rebalance
    }

    # Listen for disconnection from the cluster
    coordinator.add_listener("/v1/catalog/datacenters") { |json|
      tasks.map { |partition, task| task.terminate } if json.empty?
    }

    # Listen for disconnected instances
    coordinator.add_listener("/v1/health/state/critical") { |json|
      json.select { |h| h["ServiceID"] == config.service_id }.
        map { |h| h["Node"] }.
        each { |node| agent.force_leave(node) }
    }

    coordinator.run

  ensure
    tasks.map { |partition, task| task.terminate }
    # release partitions
    # leave cluster
  end

  def agent
    @agent ||= Agent.new do |b|
      b.logger = logger
    end
  end

  private

  attr_accessor :config, :service_name, :service_id, :service_tags, :service_port, :logger

  def log_progname
    self.class.name
  end

  def rebalance
    logger.info(log_progname) { "Rebalancing" }

    partitions.each do |partition|
      if partition.assigned_to?(config.node)
        if partition.acquired_by?(config.node)
          logger.info(log_progname) { "Partition '#{partition.id}' already acquired" }
          # Nothing to do
          
        elsif !partition.acquired_by
          logger.info(log_progname) { "Acquiring partition '#{partition.id}'" }

          partition.acquire
          tasks[partition].start
          coordinator.remove_listener(partition.consul_path)

        else
          logger.info(log_progname) { "Waiting for partition '#{partition.id}' to become available" }

          coordinator.add_listener(partition.consul_path) do
            rebalance
          end
        end
      else
        logger.info(log_progname) { "Partition '#{partition.id}' assigned to #{partition.assigned_to} (I'm #{config.node})" }

        if partition.acquired_by?(config.node)
          tasks[partition].terminate
          partition.release
          coordinator.remove_listener(partition.consul_path)
        else
          # None of our business
        end
      end
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
    @tasks ||= Hash.new do |hash, key|
      hash[key] = Task.new do |b|
        b.partition = key
        b.config = config
        # b.on_start = @on_acquiring_partition_block
        # b.on_terminate = @on_releasing_partition_block
        # b.health_checks = health_checks
        b.logger = logger
      end
    end
  end

  def coordinator
    @coordinator ||= Coordinator.new(logger: logger)
  end
end

require 'manager/agent'
require 'manager/coordinator'
require 'manager/partition'
require 'manager/partitions'
require 'manager/task'
