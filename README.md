# Manager

Process Management for Clusters

## Problem Statement

Distributed computing environments face two significant problems

* Computing resources need to be assigned to computing tasks in a coordinated
  way (ie, if I have two computers and two tasks, I don't want both of the
computers trying to do the same task)
* Process failure needs to be detected and responded to (ie if I run out of disk
  space, another process should take over my task)

An ideal solution would satisfy a couple objectives

1. 'Failure' would be defined in-process (as opposed to simply asking if an
   instance is running)
2. Task assignment would be able to tolerate instances entering & leaving the
   cluster
3. There would be no single point of failure
4. It would be language-agnostic (could be used with Ruby, Java, Node, etc)
5. Task assignment could (optionally) be static unless the cluster topology
   changed

Manager solves these problems by building a state machine on top of
[Consul](http://consul.io), providing a fault-tolerant, decentralized way to 
assign processes to instances.


## How to use it

Manager allows you to build a daemon processes to run on each
instance participating in a cluster.  To define a cluster's behavior, you write
a ruby script to define your manager and run it under supervision on each node
in the cluster.  It will take care of starting & stopping processes as the 
instance acquires work.

The first thing you'll need is a working Consul cluster, so if you don't have
that, take a minute to learn about [Consul](http://www.consul.io/).

Next, you'll need to write your daemon.  Here's an example definition for a 
cluster of Kafka consumers

```ruby
# /my_manager_daemon.rb

#!/usr/bin/env ruby
require 'manager'
require 'pagerduty'

# Create a manager and tell it where to find at least one Consul server
manager = Manager.new do |m|
  # Consul can manage multiple services, so we'll tell it which one we're defining
  # `service_id` must be unique withing a Consul cluster, but only needs to be 
  # specified if `service_name` (which is required) isn't unique
  m.service_id = 'kafka_consumer_1'
  m.service_name = 'Kafka Consumer'

  # We can set agent config settings if we need something special.  See
  # http://www.consul.io/docs/agent/options.html for supported options.
  m.consul_agent_options = {
    log_level: :warn,
    config_file: '/path/to/config',
    ca_file: '/path/to/CA/file',    # Certificate authority file for TLS
    verify_outgoing: true,          # Ensure we're talking to the real Consul
  }

  # In case you want to use Consul's tagging functionality
  m.consul_agent_tags = [:consumer]

  # We'll tell manager about the units of work we want to allocate to instances.
  # In this case we want each instance to process data from a number of Kafka
  # partitions, and we want to make sure that each partition is only processed
  # by one instance.
  m.partitions = (0...ENV['KAFKA_PARTITION_COUNT']).to_a.map(&:to_s)
  
  # This is the action we want the daemon to take when a partition is acquired 
  # by this instance.  Note that this block should be non-blocking.  Manager is
  # not intended to serve as the 'outer loop' for your entire application.
  m.on_acquiring_partition do |partition|
    # The manager exposes #exec, which executes arbitrary commands in a
    # sub-process.  This ensures that if the manager daemon dies, the processes
    # will be killed as well.
    m.exec(
      name: partition,  # The name allows us to lookup the PID later
      command: 'bundle exec ruby process_kafka_partition.rb --partition #{partition}'
    )
  end

  # Now we tell the manager how to gracefully stop doing work
  m.on_releasing_partition do |partition|
    # We'll allow the process to exit gracefully.  Manager tracks the PID's of
    # each process created with #exec, you can get them by calling #pid with the
    # name provided to #exec
    `kill(#{m.pids[partition]}, SIGTERM)`
  end

  # Let's use Consul's health checks to make sure the process is responsive.
  # Health checks come in two flavors: Script and TTL.  'Script' health checks 
  # are triggered if the return value of the script isn't 0
  # (TTL is described below)
  m.health_check_script('Make sure the process is alive') do |check, partition|
    # Health checks must have globally unique identifier
    # If your name is unique, this can be omitted
    check.id = "health_check_#{partition}"

    # ...and add a description of what's happening
    check.notes = "Sends SIGUSR1 to the process and fails if the process doesn't respond"

    # This is the script that will be run.  Our process should return 0 if it's OK
    check.script = "kill(#{m.pids[partition]}, SIGUSR1)"

    # We'll call this script once a minute
    check.interval = 1.minute

    # Now let's define how we want to respond to health-check failures
    # This block will be called when the health check enters the 'failed' state
    check.on_failure do
      # We don't really know what caused this, so we'll call in the posse
      Pagerduty.new(ENV['PAGERDUTY_SERVICE_KEY']).
        trigger("Health Check '#{check.name}' failed on partition #{partition}")
    end

    # Let's call off the posse if the problem resolves itself
    check.on_pass do
      Pagerduty.new(ENV['PAGERDUTY_SERVICE_KEY']).
        resolve("Health Check '#{check.name}' failed on partition #{partition}")
    end

    # We can also respond to the check entering the 'warn' state
    check.on_warning do
      # Whatevs 
    end
  end

  # TTL checks allow a process to tell Consul that it's doing OK
  # (rather than Consul asking it, as with Script checks)
  m.health_check_ttl("ttl_check_#{partition}") do |check, partition|
    # If the process doesn't make an HTTP request to 
    # http://localhost/v1/agent/check/pass/ttl_check_<name> for 5 minutes, 
    # the check will be triggered
    check.ttl = 5.minutes
  end
end

# If you already have Consul running, you can skip this part
manager.agent.start(server: true, bootstrap: true)
manager.agent.join('127.0.0.1')

# All done!  Let's start up the manager and start processing data
manager.run
```

All you need to do now is put `my_manager_daemon.rb` on each instance in your
cluster and use something like [God](http://godrb.com/) or
[Upstart](http://upstart.ubuntu.com/) to ensure that it stays running.

    KAFKA_PARTITION_COUNT=16 PAGERDUTY_SERVICE_KEY=key bundle exec ruby my_manager_daemon.rb

Manager will take care of announcing new instances to the cluster, assigning 
partitions to each instance, rebalancing the cluster if an instance goes down 
or is terminated and monitoring your service's health.


## How it actually works

### Preliminaries

Consul provides a mechanism for service discovery and consistent, distributed KV
store.  It provides an HTTP API which accepts blocking requests which can be
used to generate event handlers when the KV store (or the cluster topology)
changes.  Manager uses Consul to solve all the tricky problems of distributed
decision-making.


### Basic Architecture

We'll use the same basic terminology as
[Helix](http://helix.apache.org/Concepts.html): a cluster is made up of a number
of instances and a number of partitions.  Each instance processes as many
partitions as are required to fully consume the partitions.  The task is to
ensure that each partition as assigned to at-most-one instance and eventually
exactly-one instance.  (One difference between this proposal and Helix is that
I'm not building in any type of restrictions on how instances can transition
between partitions or what partitions can be co-located on an instance, ie
Master/Slave separation)

Partitions exist in one of 2 states, __assumed__ partitions have been
acknowledged by the instance which owns them, while __assigned__ partitions have
not.  Partition allocation is deterministic given a set of partitions &
instances (for example using the
[RUSH](http://www.ssrc.ucsc.edu/media/papers/honicky-ipdps04.pdf) algorithm), so
there is always a mapping from a partition to an instance, however instances
must explicitly 'assume' responsiblity for a partition.  This ensures that
partition assignment remains consistent during topology changes, and allows
instances to signal that they have released ownership of a partition and the
partition is ready to be transferred to its new owner.


### Events

The nodes need to handle a few events:
* __Rebalance__: When the cluster topology changes, a new partition mapping is
  computed.  Processing on assumed partitions which are no longer assigned is
terminated and the partitions are released.  Assigned partitions which are not
assumed are acquired as they become available and processing is started.
(Executed by all instances)
* __Update Partitions__: When a daemon first start, it updates the partition set
  to match it's local definition and triggers rebalance. (Update executed by new
instance, rebalance executed by all instances)
* __Enter__: When an instance enters the cluster it registers itself with the
  cluster and executes a rebalance. (Executed by the instance entering the
cluster)
* __Leave__: When an instance leaves the cluster, it terminates processing on
  assumed partitions, releases its assumed partitions and deregisters itself
from the cluster. (Executed by the instance leaving the cluster)
* __Local failure__: When an instance loses its connection to the cluster, it
  terminates processing on assumed partitions. (Executed by the instance which
failed)
* __Remote failure__: When an instance become unresponsive, its partitions are
  released and it is deregistered from the cluser by another instance. (Executed
by all instances)
* __Health check failure__: When an instance's health check fails, it optionally
  executes user-defined handlers - we make no assumptions about the implications
of a health check fail. (Executed by the instance whose health-check failed)


### Actions

To accomplish these events, the following actions need to be implemented:

* Compute partition map based on the cluster topology and the instance's
  identity
* Update the partition set
* Transition from one partition map to another
* Enter the cluster
* Leave the cluster
* Force another node to leave the cluster
* Listen for topology changes
* Listen for partition asignment changes
* Listen for partition set changes
* Begin processing
* Terminate processing
* Acquire a partition
* Release a partition
* Respond to a failing health check
