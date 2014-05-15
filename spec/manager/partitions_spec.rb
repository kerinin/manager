describe Manager::Partitions do
  let(:config) do
    double("Config", service_id: :service_id)
  end

  let(:partitions) do
    Manager::Partitions.new do |b|
      b.agent = fake_agent
      b.config = config
      b.partitioner = Manager::Partitions::LinearPartitioner
    end
  end

  describe "#each" do
    context "with a single instance" do
      let(:fake_agent) do
        double(
          "Agent", 
          get_service_health: [
            {
              "Node" => {"Node" => "instance1"},
              "Service" => {},
              "Checks" => [
                {
                  "Node" => "isntance1",
                  "Status" => "passing",
                  "ServiceID" => "service_id",
                }
              ]
            }
          ],
          get_keys: {
            'service_id/partitions' => OpenStruct.new(value: ['partition1', 'partition2'])
          },
        )
      end

      it "assigns all partitions to the node" do
        expect(partitions.map(&:assigned_to)).to eq(['instance1', 'instance1'])
      end
    end

    context "with healthy instances" do
      let(:fake_agent) do
        double(
          "Agent", 
          get_service_health: [
            {
              "Node" => {"Node" => "instance1"},
              "Service" => {},
              "Checks" => [
                {
                  "Node" => "isntance1",
                  "Status" => "passing",
                  "ServiceID" => "service_id",
                }
              ]
            },
            {
              "Node" => {"Node" => "instance2"},
              "Service" => {},
              "Checks" => [
                {
                  "Node" => "isntance1",
                  "Status" => "passing",
                  "ServiceID" => "service_id",
                }
              ]
            }
          ],
          get_keys: {
            'service_id/partitions' => OpenStruct.new(value: ['partition1', 'partition2'])
          },
        )
      end

      it "splits partitions across nodes" do
        expect(partitions.map(&:assigned_to)).to eq(['instance1', 'instance2'])
      end
    end

    context "with unhealthy instances" do
      let(:fake_agent) do
        double(
          "Agent", 
          get_service_health: [
            {
              "Node" => {"Node" => "instance1"},
              "Service" => {},
              "Checks" => [
                {
                  "Node" => "isntance1",
                  "Status" => "passing",
                  "ServiceID" => "service_id",
                }
              ]
            },
            {
              "Node" => {"Node" => "instance2"},
              "Service" => {},
              "Checks" => [
                {
                  "Node" => "isntance1",
                  "Status" => "failing",
                  "ServiceID" => "service_id",
                }
              ]
            }
          ],
          get_keys: {
            'service_id/partitions' => OpenStruct.new(value: ['partition1', 'partition2'])
          },
        )
      end

      it "assigns all partitions to healthy nodes" do
        expect(partitions.map(&:assigned_to)).to eq(['instance1', 'instance1'])
      end
    end
  end

  describe "#save" do
  end
end
