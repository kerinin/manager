describe "Integration" do
  describe "Allocating a single partition to a single instance" do
    let(:acquired) { [] }
    let(:released) { [] }

    let(:manager) do
      Manager.new(consul_servers: ['127.0.0.1']) do |m|
        m.service_name = 'service_name'

        m.consul_agent_options = {server: true, bootstrap: true, node: 'node'}

        m.partitions = ['partition']

        m.on_acquiring_partition do |partition|
          acquired << partition
        end

        m.on_releasing_partition do |partition|
          released << partition
        end
      end
    end

    it "assigns partition" do
      thr = Thread.new { manager.run }
      sleep 10
      thr.kill

      expect(acquired).to include('partition')
    end

    it "releases partition" do
      thr = Thread.new { manager.run }
      sleep 10
      thr.kill
      sleep 10

      expect(released).to include('partition')
    end
  end
end
