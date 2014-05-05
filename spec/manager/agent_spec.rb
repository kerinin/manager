describe Manager::Agent do
  # NOTE: This assumes Consul is available locally
  let(:agent) { Manager::Agent.new(consul_servers: ['127.0.0.1']) }

  describe "#start" do
    after(:each) do
      `consul leave`
    end

    it "starts the agent" do
      pending "takes too long"
      agent.start

      expect(`consul info`).to match(/agent/)
    end
  end

  describe "#join" do
    before(:each) { agent.start }

    it "sends expected request" do
      stub_request(:get, "http://localhost/v1/agent/join/127.0.0.1")
      agent.join
      expect(WebMock).to have_requested(:get, "http://localhost/v1/agent/join/127.0.0.1")
    end

    it "accepts queryargs" do
      stub_request(:get, "http://localhost/v1/agent/join/127.0.0.1").with(query: {wan: 1})
      agent.join do |b|
        b.queryargs = {wan: 1}
      end
      expect(WebMock).to have_requested(:get, "http://localhost/v1/agent/join/127.0.0.1").with(query: {wan: 1})
    end

    it "returns true on 200 response" do
      stub_request(:get, "http://localhost/v1/agent/join/127.0.0.1")
      expect(agent.join).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:get, "http://localhost/v1/agent/join/127.0.0.1").to_return(status: 500)
      expect { agent.join }.to raise_error(Faraday::Error::ClientError)
    end
  end

  describe "#get_key" do
    before(:each) { agent.start }

    it "sends expected request" do
      stub_request(:get, "http://localhost/v1/kv/foo")
      agent.get_key(:foo)
      expect(WebMock).to have_requested(:get, "http://localhost/v1/kv/foo")
    end

    it "accepts queryargs" do
      stub_request(:get, "http://localhost/v1/kv/foo").with(query: {dc: 'dc'})
      agent.get_key(:foo) do |b|
        b.queryargs = {dc: 'dc'}
      end
      expect(WebMock).to have_requested(:get, "http://localhost/v1/kv/foo").with(query: {dc: 'dc'})
    end

    it "returns json on 200 response" do
      body = [
        {
          "CreateIndex" => 100,
          "ModifyIndex" => 200,
          "Key" => "foo",
          "Flags" => 0,
          "Value" => "dGVzdA=="
        }
      ]
      stub_request(:get, "http://localhost/v1/kv/foo").
        to_return(body: JSON.dump(body))

      expect(agent.get_key(:foo)).to eq(body)
    end

    it "raises exception on non-200 response" do
      stub_request(:get, "http://localhost/v1/kv/foo").to_return(status: 500)
      expect { agent.get_key(:foo) }.to raise_error(Faraday::Error::ClientError)
    end
  end

  describe "#put_key" do
    before(:each) { agent.start }

    it "sends expected request" do
      stub_request(:put, "http://localhost/v1/kv/foo")
      agent.put_key(:foo, :bar)
      expect(WebMock).to have_requested(:put, "http://localhost/v1/kv/foo").with(body: :bar)
    end

    it "accepts queryargs" do
      stub_request(:put, "http://localhost/v1/kv/foo").with(query: {dc: 'dc'})
      agent.put_key(:foo, :bar) do |b|
        b.queryargs = {dc: 'dc'}
      end
      expect(WebMock).to have_requested(:put, "http://localhost/v1/kv/foo").with(body: :bar, query: {dc: 'dc'})
    end

    it "returns true on 200 response" do
      stub_request(:put, "http://localhost/v1/kv/foo").
        to_return(body: 'true')

      expect(agent.put_key(:foo, :bar)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:put, "http://localhost/v1/kv/foo").
        to_return(status: 500)

      expect { agent.put_key(:foo, :bar) }.to raise_error(Faraday::Error::ClientError)
    end

    it "raises exception on CAS failure" do
      stub_request(:put, "http://localhost/v1/kv/foo").
        to_return(body: 'false')

      expect { agent.put_key(:foo, :bar) }.to raise_error(Manager::Agent::CASException)
    end
  end

  describe "#delete_key" do
  end

  describe "#register_check" do
  end

  describe "#force_leave" do
  end

  describe "#leave" do
    it "stops the agent" do
      pending "takes too long"
      agent.start
      agent.leave
      sleep 4

      expect(`consul info`).to match(/Error connecting to Consul/)
    end
  end
end
