require "assembler"
require "manager/version"
require "consistent_hashing"
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'logger'

class Manager

  def initialize(options = {})
    @logger = options[:logger] || Logger.new(STDOUT)

    yield self
  end

  attr_accessor :service_name, :service_id, :service_tags, :service_port, :logger

  def log_progname
    self.class.name
  end

  def service_id
    @service_id || service_name
  end

  def consul_agent_tags(tags)
    @consul_agent_tags = tags
  end

  def partitions=(partitions)
    @initial_partitions = partitions
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

  def pids
    @pids ||= {}
  end

  def exec(name, script)
    pid = Process.fork
    if pid.nil?
      exec script
    else
      pids[name] = pid
    end
  end

  def run
    validate!
    agent.register_service(service_definition)

    listeners = []

    partitions.save(@initial_partitions)
    # health_checks.each { |k,v| agent.register_check(v.as_json) }

    # Listen for changes to instance set
    coordinator.add_listener("/v1/catalog/service/#{service_id}") { |json|
      rebalance
    }

    # Listen for changes to partition set
    coordinator.add_listener("/v1/kv/#{service_id}/partitions") { |json|
      rebalance
    }

    # Listen for changes to health checks
    # listeners << Listener.new("http://localhost/v1/agent/checks").each do |json|
    #   json.each do |k,v|
    #     @health_checks[k].handle(v) if @health_checks.has_key?(k)
    #   end
    # end

    # Listen for disconnection from the cluster
    coordinator.add_listener("/v1/catalog/datacenters") { |json|
      tasks.map { |partition, task| task.terminate } if json.empty?
    }

    # Listen for disconnected instances
    coordinator.add_listener("/v1/health/state/critical") { |json|
      json.select { |h| h["ServiceID"] == service_name }.
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

  def my_hostname
    @hostname ||= `hostname`.chomp
  end

  def validate!
    raise ArgumentError, 'Service Name missing' unless @service_name
  end

  def rebalance
    logger.info(log_progname) { "Rebalancing" }

    partitions.each do |partition|
      if partition.assigned_to?(my_hostname)
        if partition.acquired_by?(my_hostname)
          logger.info(log_progname) { "Partition '#{partition.partition_key}' already acquired" }
          # Nothing to do
          
        elsif !partition.acquired_by
          logger.info(log_progname) { "Acquiring partition '#{partition.partition_key}'" }

          partition.acquire
          tasks[partition].start
          coordinator.remove_listener(partition.consul_path)

        else
          logger.info(log_progname) { "Waiting for partition '#{partition.partition_key}' to become available" }

          coordinator.add_listener(partition.consul_path) do
            rebalance
          end
        end
      else
        logger.info(log_progname) { "Partition '#{partition.partition_key}' assigned to #{partition.assigned_to} (I'm #{my_hostname})" }

        if partition.acquired_by?(my_hostname)
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
      b.service_id = service_id
      b.partitions_key = [service_id, :partitions].join('/')
      b.logger = logger
    end
  end

  def tasks
    @tasks ||= Hash.new do |hash, key|
      hash[key] = Task.new do |b|
        b.partition = key
        b.on_start = @on_acquiring_partition_block
        b.on_terminate = @on_releasing_partition_block
        # b.health_checks = health_checks
        b.logger = logger
      end
    end
  end

  def coordinator
    @coordinator ||= Coordinator.new(logger: logger)
  end

  def service_definition
    {
      ID: service_id,
      Name: service_name,
      Tags: service_tags,
      Port: service_port,
    }
  end
end

require 'manager/agent'
require 'manager/coordinator'
require 'manager/partition'
require 'manager/partitions'
require 'manager/task'
