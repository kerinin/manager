describe Manager::Coordinator do
  before(:each) { Thread.abort_on_exception = true }

  let(:collector) { [] }
  
  let(:coordinator) do
    Manager::Coordinator.new
  end

  describe "#add_listener" do
    after(:each) { coordinator.kill }

    it "calls passed block with unique updated response values" do
      called = false

      stub_request(:get, "http://127.0.0.1:8500/foo").
        to_return(body: '["json1"]', headers: {'X-Consul-Index' => 1})
      stub_request(:get, "http://127.0.0.1:8500/foo?wait=10m&index=1").
        to_return(body: '["json2"]', headers: {'X-Consul-Index' => 2})
      stub_request(:get, "http://127.0.0.1:8500/foo?wait=10m&index=2").
        to_return(body: '["json2"]', headers: {'X-Consul-Index' => 2})

      coordinator.add_listener('/foo') do |json|
        collector << json
      end
      sleep 1
      coordinator.drain_work_queue

      expect(collector).to eq([['json1'], ['json2']])
    end
  end

  describe "#kill" do
  end
end
