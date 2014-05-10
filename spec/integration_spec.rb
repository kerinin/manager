describe "Integration" do
  before(:each) do
    Thread.abort_on_exception = true
    WebMock.allow_net_connect!
  end

  context "with a single partition and a single instance" do
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

describe "Rebalance" do
  it "acquires available partitions"
  it "releases partitions no longer assigned"
end

describe "Update Partitions" do
  it "allocates new partitions to instances"
  it "terminates removed partitions"
end

describe "Enter Cluster" do
  it "allocates partitions to new instance"
  it "terminates partitions from existing instances"
end

describe "Leave Cluster" do
  it "allocates partitions to active instances"
  it "terminates partitions from exiting instances"
end

describe "Remote Failure" do
  it "allocates failed partitions to healthy instances"
end

describe "Local Failure" do
  it "terminates tasks"
end
