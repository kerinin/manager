class Manager
  class Task
    extend Assembler

    assemble_from(:partition, :on_start, :on_terminate)

    def start
      on_start.call partition
    end

    def terminate
      on_terminate.call partition
    end
  end
end
