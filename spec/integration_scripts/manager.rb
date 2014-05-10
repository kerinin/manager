require 'manager'

manager = Manager.new do |m|
  m.service_name = 'integration_service'

  m.partitions = (0...20).to_a

  m.on_acquiring_partition do |partition|
    puts "-----> Acquired partition #{partition}"
  end

  m.on_releasing_partition do |partition|
    puts "-----> Releasing partition #{partition}"
  end
end

manager.run
