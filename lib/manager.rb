require "assembler"
require "manager/version"
require "consistent_hashing"
require 'faraday'
require 'faraday_middleware'
require 'json'

class Manager

  def initialize(options = {})
    @consul_servers = options[:consul_servers]

    yield self
  end

  attr_accessor :service_name, :service_id

  def consul_agent_options=(hash)
    @consul_agent_options = hash
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
    listeners = []

    agent.begin(@consul_agent_options, @consul_agent_tags)
    agent.join
    partitions.save(@initial_partitions)
    # health_checks.each { |k,v| agent.register_check(v.as_json) }

    # Listen for changes to instance set
    coordinator.add_listener("http://localhost/v1/catalog/service/#{service_id}") { |json|
      rebalance
    }

    # Listen for changes to partition set
    coordinator.add_listener("http://localhost/v1/kv/#{service_id}/partitions") { |json|
      rebalance
    }

    # Listen for changes to health checks
    # listeners << Listener.new("http://localhost/v1/agent/checks").each do |json|
    #   json.each do |k,v|
    #     @health_checks[k].handle(v) if @health_checks.has_key?(k)
    #   end
    # end

    # Listen for disconnection from the cluster
    coordinator.add_listener("http://localhost/v1/catalog/datacenters") { |json|
      tasks.map { |partition, task| task.terminate } if json.empty?
    }

    # Listen for disconnected instances
    coordinator.add_listener("http://localhost/v1/health/state/critical") { |json|
      json.select { |h| h["ServiceID"] == service_name }.
        map { |h| h["Node"] }.
        each { |node| agent.force_leave(node) }
    }

    # NOTE: this probably needs more thought
    %w(INT TERM).each do |sig|
      trap sig do
        tasks.map { |partition, task| task.terminate }
        # release partitions
        # leave cluster
      end
    end

    coordinator.run
  end

  private

  def rebalance
    partitions.each do |partition|
      if partition.assigned_to?(self)
        if partition.acquired_by?(self)
          # Nothing to do
          
        elsif !partition.acquired_by
          partition.acquire
          tasks[partition].start
          partition_listeners.delete(partition.name)

        else
          # NOTE: Unconstrained object growth ahoy!
          listeners << Listener.new("http://localhost/v1/kv/#{service_id}/partition/#{partition.name}").each do
            rebalance
          end
        end
      else
        if partition.acquired_by?(self)
          tasks[partition].terminate
          partition.release
          partition_listeners.delete(partition.name)
        else
          # None of our business
        end
      end
    end
  end

  def agent
    @agent ||= Agent.new do |b|
      b.consul_servers = @consul_servers
      b.service_name = @service_name
      b.service_id = @service_id if @service_id
    end
  end

  def partitions
    Partitions.new do |b|
      b.agent = agent
    end
  end

  def tasks
    @tasks ||= Hash.new do |hash, key|
      hash[key] = Tasks.new do |b|
        b.partition = key
        b.on_start = @on_acquiring_partition_block
        b.on_terminate = @on_releasing_partition_block
        # b.health_checks = health_checks
      end
    end
  end

  def coordinator
    @coordinator ||= Coordinator.new
  end
end

require 'manager/agent'
require 'manager/coordinator'
require 'manager/listener'
require 'manager/partition'
require 'manager/partitions'
require 'manager/task'
