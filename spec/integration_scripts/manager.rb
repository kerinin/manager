require 'manager'

manager = Manager.new do |m|
  m.service_name = 'integration_service'

  m.partitions = (0...20).to_a
  m.max_active_partitions = 2
  m.task_cycle_interval = 10

  m.on_acquiring_partition do |partition|
    puts "-----> Starting partition #{partition}"
  end

  m.on_releasing_partition do |partition|
    puts "-----> Stopping partition #{partition}"
  end
end

manager.run
