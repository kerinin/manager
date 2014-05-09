describe "Integration" do
  before(:each) do
    Thread.abort_on_exception = true
    WebMock.allow_net_connect!
  end

  describe "Allocating a single partition to a single instance" do
    let(:acquired) { [] }
    let(:released) { [] }

    let(:manager) do
      Manager.new do |m|
        m.service_name = 'service_name'

        m.partitions = ['partition']

        m.on_acquiring_partition do |partition|
          acquired << partition
        end

        m.on_releasing_partition do |partition|
          released << partition
        end
      end
    end

    it "assigns partition", integration: true do
      thr = Thread.new { manager.run }
      # manager.run

      sleep 10
      thr.kill

      expect(acquired).to include('partition')
    end

    it "releases partition", integration: true do
      thr = Thread.new { manager.run }
      sleep 10
      thr.kill
      sleep 10

      expect(released).to include('partition')
    end
  end
end
