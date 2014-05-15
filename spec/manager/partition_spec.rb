describe Manager::Partition do
  let(:fake_agent) { double("Agent", put_key: true) }

  let(:fake_config) { double("Config", node: :foo, service_id: :service_id) }

  let(:remote_value) { OpenStruct.new(value: 'foo') }

  let(:partition_args) do
    {
      id: :partition_id,
      agent: fake_agent,
      config: fake_config,
      assigned_to: :assigned_to,
      remote_value: remote_value,
    }
  end

  let(:partition) do
    Manager::Partition.new(partition_args)
  end

  describe "#assigned_to" do
    it "returns instance variable value" do
      expect(partition.assigned_to).to eq(:assigned_to)
    end
  end

  describe "#assigned_to?" do
    it "returns true if partition is assigned to the passed instance" do
      expect(partition.assigned_to?('assigned_to')).to be_true
    end

    it "returns false if partition isn't assigned to the passed instance" do
      expect(partition.assigned_to?('nope')).to be_false
    end
  end

  describe "#acquired_by" do
    it "returns the remote partition value" do
      expect(partition.acquired_by).to eq('foo')
    end

    it "returns nil if no remote partition value defined" do
      pending "Think more about the missing key semantics"

      allow(fake_agent).to receive(:get_key).
        with('v1/kv/partition_id').and_return(OpenStruct.new(value: nil))

      expect(partition.acquired_by).to eq(nil)
    end
  end

  describe "#acquired_by?" do
    it "returns true if the passed instance matches the remote partition value" do
      expect(partition.acquired_by?(:foo)).to be_true
    end

    it "returns false if the passed instance doesn't match the remote partition value" do
      expect(partition.acquired_by?(:bar)).to be_false
    end
  end

  describe "#acquire" do
    it "doesn't modify remote partition if its value is already equal to service_id" do
      partition_args.merge!(assigned_to: :service_id)

      expect(fake_agent).to_not receive(:put_key)

      partition.acquire
    end

    it "check-and-sets remote partition value to service_id" do
      partition_args.merge!(assigned_to: :service_id)
      allow(remote_value).to receive(:value).and_return(nil)
      allow(remote_value).to receive(:modify_index).and_return(100)

      expect(fake_agent).to receive(:put_key).
        with("service_id/p_partition_id", :foo, cas: 100)

      partition.acquire
    end
    
    it "raises error if assigned_to value doesn't match node" do
      allow(partition).to receive(:assigned_to).and_return('foo')
      allow(fake_config).to receive(:node).and_return('bar')

      expect { partition.acquire }.to raise_error(Manager::Partition::IllegalModificationException)
    end

    it "raises error if remote partition value refers to another node" do
      allow(remote_value).to receive(:value).and_return('bar')

      expect { partition.acquire }.to raise_error(Manager::Partition::IllegalModificationException)
    end

    it "raises error if CAS operation fails" do
      pending "This seems like an Agent test, no?"
    end
  end

  describe "#release" do
    it "doesn't modify remote partition if its value is already nil" do
      allow(remote_value).to receive(:value).and_return(nil)

      expect(fake_agent).to_not receive(:put_key)

      partition.release
    end

    it "check-and-sets remote partition value to nil" do
      allow(remote_value).to receive(:value).and_return('foo')
      allow(remote_value).to receive(:modify_index).and_return(100)

      expect(fake_agent).to receive(:put_key).
        with('service_id/p_partition_id', nil, cas: 100)

      partition.release
    end

    it "doesn't modify remote partition if remote partition value doesn't match node" do
      allow(remote_value).to receive(:value).and_return('bar')

      expect(fake_agent).to_not receive(:put_key)

      partition.release
    end

    it "raises error if CAS operation fails" do
      pending "This seems like an Agent test, no?"
    end
  end
end
