describe Manager::Task do
  let(:on_start) { double('StartBlock', call: true) }
  let(:on_terminate) { double('TerminateBlock', call: true) }

  let(:task) do
    Manager::Task.new(partition: 'partition1', on_start: on_start, on_terminate: on_terminate)
  end

  describe "#start" do
    it "calls start block with partition" do
      expect(on_start).to receive(:call).with('partition1')

      task.start
    end
  end

  describe "#terminate" do
    it "calls terminate block with partition" do
      expect(on_terminate).to receive(:call).with('partition1')

      task.terminate
    end
  end
end
