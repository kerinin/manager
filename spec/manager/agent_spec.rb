describe Manager::Agent do
  # NOTE: This assumes Consul is available locally
  let(:agent) { Manager::Agent.new }

  describe "#start" do
    after(:each) do
      `consul leave`
    end

    it "starts the agent", integration: true do
      agent.start

      expect(`consul info`).to match(/agent/)
    end
  end

  describe "#join" do
    it "sends expected request" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/join/127.0.0.1")
      agent.join('127.0.0.1')
      expect(WebMock).to have_requested(:get, "http://127.0.0.1:8500/v1/agent/join/127.0.0.1")
    end

    it "returns true on 200 response" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/join/127.0.0.1")
      expect(agent.join('127.0.0.1')).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/join/127.0.0.1").to_return(status: 500)
      expect { agent.join('127.0.0.1') }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#get_key" do
    it "sends expected request" do
      stub_request(:get, "http://127.0.0.1:8500/v1/kv/foo").to_return(body: '[]')
      agent.get_key(:foo)
      expect(WebMock).to have_requested(:get, "http://127.0.0.1:8500/v1/kv/foo")
    end

    it "accepts queryargs" do
      stub_request(:get, "http://127.0.0.1:8500/v1/kv/foo").with(query: {dc: 'dc'}).to_return(body: '[]')
      agent.get_key(:foo, dc: 'dc')

      expect(WebMock).to have_requested(:get, "http://127.0.0.1:8500/v1/kv/foo").with(query: {dc: 'dc'})
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
      response = OpenStruct.new(
        value: Base64.decode64("dGVzdA=="),
        create_index: 100,
        modify_index: 200,
        flags: 0
      )
      stub_request(:get, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(body: JSON.dump(body))

      expect(agent.get_key(:foo)).to eq(response)
    end

    it "raises exception on non-200 response" do
      stub_request(:get, "http://127.0.0.1:8500/v1/kv/foo").to_return(status: 500)
      expect { agent.get_key(:foo) }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#put_key" do
    it "sends expected request" do
      stub_request(:put, "http://127.0.0.1:8500/v1/kv/foo")
      agent.put_key(:foo, :bar)
      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/kv/foo").with(body: YAML.dump(:bar))
    end

    it "accepts queryargs" do
      stub_request(:put, "http://127.0.0.1:8500/v1/kv/foo").with(query: {dc: 'dc'})
      agent.put_key(:foo, :bar, dc: 'dc')

      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/kv/foo").with(body: YAML.dump(:bar), query: {dc: 'dc'})
    end

    it "returns true on 200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(body: 'true')

      expect(agent.put_key(:foo, :bar)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(status: 500)

      expect { agent.put_key(:foo, :bar) }.to raise_error(Manager::Agent::HTTPServerError)
    end

    it "raises exception on CAS failure" do
      stub_request(:put, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(body: 'false')

      expect { agent.put_key(:foo, :bar) }.to raise_error(Manager::Agent::CASException)
    end
  end

  describe "#delete_key" do
    it "sends expected request" do
      stub_request(:delete, "http://127.0.0.1:8500/v1/kv/foo")
      agent.delete_key(:foo)
      expect(WebMock).to have_requested(:delete, "http://127.0.0.1:8500/v1/kv/foo")
    end

    it "accepts queryargs" do
      stub_request(:delete, "http://127.0.0.1:8500/v1/kv/foo").with(query: {dc: 'dc'})
      agent.delete_key(:foo, dc: 'dc')

      expect(WebMock).to have_requested(:delete, "http://127.0.0.1:8500/v1/kv/foo").with(query: {dc: 'dc'})
    end

    it "returns true on 200 response" do
      stub_request(:delete, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(body: 'true')

      expect(agent.delete_key(:foo)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:delete, "http://127.0.0.1:8500/v1/kv/foo").
        to_return(status: 500)

      expect { agent.delete_key(:foo) }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#register_service" do
    it "sends expected request" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/service/register")
      agent.register_service(Name: :service)
      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/agent/service/register").with(body: JSON.dump(Name: :service))
    end

    it "accepts queryargs" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/service/register").with(query: {dc: 'dc'})
      agent.register_service({Name: :service}, dc: 'dc')

      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/agent/service/register").with(query: {dc: 'dc'})
    end

    it "returns true on 200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/service/register")

      expect(agent.register_service(Name: :service)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/service/register").
        to_return(status: 500)

      expect { agent.register_service(Name: :service) }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#register_check" do
    it "sends expected request" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/check/register")
      agent.register_check({foo: :bar})
      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/agent/check/register").with(body: JSON.dump(foo: :bar))
    end

    it "accepts queryargs" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/check/register").with(query: {dc: 'dc'})
      agent.register_check(:foo, dc: 'dc')

      expect(WebMock).to have_requested(:put, "http://127.0.0.1:8500/v1/agent/check/register").with(query: {dc: 'dc'})
    end

    it "returns true on 200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/check/register")

      expect(agent.register_check(:foo)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:put, "http://127.0.0.1:8500/v1/agent/check/register").
        to_return(status: 500)

      expect { agent.register_check(:foo) }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#force_leave" do
    it "sends expected request" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo")
      agent.force_leave(:foo)
      expect(WebMock).to have_requested(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo")
    end

    it "accepts queryargs" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo").with(query: {wan: 1})
      agent.force_leave(:foo, wan: 1)

      expect(WebMock).to have_requested(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo").with(query: {wan: 1})
    end

    it "returns true on 200 response" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo")
      expect(agent.force_leave(:foo)).to be_true
    end

    it "raises exception on non-200 response" do
      stub_request(:get, "http://127.0.0.1:8500/v1/agent/force-leave/foo").to_return(status: 500)
      expect { agent.force_leave(:foo) }.to raise_error(Manager::Agent::HTTPServerError)
    end
  end

  describe "#leave" do
    it "stops the agent", integration: true do
      pending "takes too long"
      agent.start
      agent.leave
      sleep 4

      expect(`consul info`).to match(/Error connecting to Consul/)
    end
  end
end
