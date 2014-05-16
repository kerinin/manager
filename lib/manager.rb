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
      Kernel.exec script
    else
      pids[name] = pid
    end
  end

  def self.daemons
    @daemons ||= {}
  end

  def self.daemonize(name, &block)
    daemons[name] = Daemons.call(name, multiple: true) do
      block.call
    end
  end

  def initialize(options = {})
    @logger = options[:logger] || Logger.new(STDOUT)
    @logger.level = Logger::INFO
    # @logger.level = Logger::DEBUG
    @config = Configuration.new

    yield @config

    @config.validate!
  end

  def run
    agent.register_service(config.service_definition)

    partitions.save(config.partitions)

    event_handler.on_instance_set_changes do
      rebalance
    end

    event_handler.on_partition_set_changes do
      rebalance
    end

    event_handler.on_node_failure do |failing_node|
      force_release_partitions_for(failing_node)
      agent.force_leave(failing_node)
    end

    coordinator.add_timer(:cycle_tasks, config.task_cycle_interval) do
      tasks.cycle
    end

    coordinator.run

  ensure
    tasks.terminate_all
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

  def rebalance
    Rebalancer.new(
      config: config,
      partitions: partitions,
      tasks: tasks,
      coordinator: coordinator,
      logger: logger,
    ).rebalance
  end

  def force_release_partitions_for(node)
    failed_partitions = partitions.select do |partition|
      failing_nodes.include?(partition.acquired_by)
    end
    failed_partitions.each { |p| p.release(true) }

    logger.debug(log_progname) { "Force-released node's #{failed_partitions.count} partitions: #{failed_partitions.map(&:id)}" }
  end

  def log_progname
    self.class.name
  end

  def partitions
    Partitions.new do |b|
      b.agent = agent
      b.config = config
      b.logger = logger
    end
  end

  def coordinator
    @coordinator ||= Coordinator.new(logger: logger)
  end

  def event_handler
    @event_handler ||= EventHandler.new(
      logger: logger,
      config: config,
      coordinator: coordinator,
    )
  end

  def tasks
    @tasks ||= Tasks.new(
      config: config,
      coordinator: coordinator,
      logger: logger,
    )
  end
end

require 'manager/agent'
require 'manager/configuration'
require 'manager/coordinator'
require 'manager/event_handler'
require 'manager/partition'
require 'manager/partition_rebalancer'
require 'manager/partitions'
require 'manager/rebalancer'
require 'manager/task'
require 'manager/tasks'
