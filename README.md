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


## Use

Manager is intended to be used to build daemon processes which run on each
instance participating in a cluster.  To define a cluster's behavior, you build
a ruby script which defines your manager and run it under supervision.  It will
take care of starting & stopping processes as the instance acquires work.

Here's an example definition for a cluster of Kafka consumers

```ruby
# /my_manager_daemon.rb
#!/usr/bin/env ruby
require 'manager'

# Create a manager and tell it where to find at least on Consul server
manager = Manager.new(consul_servers: [192.168.1.1]) do |m|
  # Consul can manage multiple services, so we'll tell it which one we're defining
  m.service_name = 'my awesome service'

  # We'll tell manager about the units of work we want to allocate to instances
  # In this case we want each instance to process data from a number of Kafka
  # partitions, and we want to make sure that each partition is only processed
  # by one instance.
  m.partitions = (0...ENV['KAFKA_PARTITION_COUNT']).to_a.map(&:to_s)
  
  # This is the action we want the manager to take when a partition is allocated
  # to this instance.  
  m.on_acquiring_partition do |partition|
    # The manager exposes #exec, which executes arbitrary commands in a
    # sub-process.  This ensures that if the manager daemon dies, the processes
    # will be killed as well.
    m.exec 'bundle exec ruby process_kafka_partition.rb --partition #{partition}'
  end

  # Now we tell the manager how to gracefully stop doing work
  m.on_releasing_partition do |partition|
    # We'll allow the process to exit gracefully
    m.sigterm(partition)
  end

  # Let's use Consul's health checks to make sure the process is responsive
  # Health checks come in two flavors: Script and TTL.  Script health checks are
  # triggered if the return value of the script isn't 0 (TTL is described below)
  m.health_check_script do |check, partition|
    # Health checks must have globally unique identifier
    check.id = "health_check_#{partition}"

    # But we can give it a more descriptive name
    check.name = "Make sure the process is alive"

    # ...and add a description of what's happening
    check.notes = "Sends SIGUSR1 to the process and fails if the process doesn't respond"

    # This is the script that will be run.  It should return 0 if the process is healthy
    check.script = "kill(#{m.pid(partition)}, SIGUSR1)"

    # We'll call this script once a minute
    check.interval = 1.minute
  end

  # TTL checks allow a process to tell Consul that it's doing OK (rather than
  # Consul asking it, as with Script checks)
  m.health_check_ttl do |check, partition|
    # ID's are optional, if you name is unique
    check.name = "Data being processed for partition #{partition}"

    # If the process doesn't make an HTTP request to 
    # http://localhost/v1/agent/check/pass/<name> for 5 minutes, the check 
    # will be triggered
    check.ttl = 5.minutes
  end

  # Now let's define how we want to respond to health-check failures
  # This block will be called with the check status and partition, the status
  # will look something like this:
  # {
  #     "Node": "foobar",
  #     "CheckID": "service:redis",
  #     "Name": "Service 'redis' check",
  #     "Status": "passing",
  #     "Notes": "",
  #     "Output": "",
  #     "ServiceID": "redis",
  #     "ServiceName": "redis"
  # }
  m.on_health_check_failure do |check_status, partition|
    # We don't really know what caused this, so we'll call in the posse
    Pagerduty.new(ENV['PAGERDUTY_SERVICE_KEY']).
      trigger("Health Check '#{check_status["ServiceName"]}' failed on partition #{partition}")
  end
end

# All done!  Let's start up the manager and start processing data
manager.run
```

All you need to do now is put `my_manager_daemon.rb` on each instance in your
cluster and use something like [God](http://godrb.com/) or
[Upstart](http://upstart.ubuntu.com/) to ensure that it stays running.  Manager
will take care of announcing new instances to the cluster, assigning partitions
to each instance, rebalancing the cluster if an instance goes down or is
terminated and monitoring your service's health.


## How it actually works
