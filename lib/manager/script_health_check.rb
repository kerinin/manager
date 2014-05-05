class Manager
  class ScriptHealthCheck
    def initialize(name, partition, &block)
      @name = name
      @partition = name
      block.call(self, partition)
    end

    attr_accessor :id, :notes, :script, :interval
    attr_reader :on_pass_block, :on_warning_block, :on_failure_block

    def on_pass(&block)
      @on_pass_block = block
    end

    def on_warning(&block)
      @on_warning_block = block
    end

    def on_failure(&block)
      @on_failure_block = block
    end
  end
end
