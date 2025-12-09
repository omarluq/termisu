require "../../../spec_helper"

describe Termisu::Event::Source::Input do
  describe "#initialize" do
    it "creates with reader and parser" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        source.should be_a(Termisu::Event::Source)
        source.running?.should be_false
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "is not running initially" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        source.running?.should be_false
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "#name" do
    it "returns 'input'" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        source.name.should eq("input")
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "#start" do
    it "sets running to true" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.running?.should be_true

        source.stop
        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "prevents double-start (idempotent)" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.running?.should be_true

        # Second start should be a no-op
        source.start(channel)
        source.running?.should be_true

        source.stop
        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "#stop" do
    it "sets running to false" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.running?.should be_true

        source.stop
        source.running?.should be_false

        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "is idempotent (can be called multiple times)" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.stop
        source.stop # Second stop should not raise
        source.running?.should be_false

        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "can be called when not started" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        # Should not raise
        source.stop
        source.running?.should be_false
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "#running?" do
    it "returns false before start" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        source.running?.should be_false
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns true after start" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.running?.should be_true

        source.stop
        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns false after stop" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)
        source.stop
        source.running?.should be_false

        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "event routing" do
    it "sends Key events to channel" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)

        # Write 'a' to the pipe
        bytes = Bytes['a'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # Wait for event with timeout
        select
        when event = channel.receive
          event.should be_a(Termisu::Event::Key)
          event.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::LowerA)
        when timeout(100.milliseconds)
          fail "Timeout waiting for key event"
        end

        source.stop
        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "sends multiple events in order" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        source.start(channel)

        # Write 'ab' to the pipe
        bytes = Bytes['a'.ord.to_u8, 'b'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # First event
        select
        when event = channel.receive
          key_event = event.as(Termisu::Event::Key)
          key_event.char.should eq('a')
        when timeout(100.milliseconds)
          fail "Timeout waiting for first key event"
        end

        # Second event
        select
        when event = channel.receive
          key_event = event.as(Termisu::Event::Key)
          key_event.char.should eq('b')
        when timeout(100.milliseconds)
          fail "Timeout waiting for second key event"
        end

        source.stop
        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "#poll_sync" do
    it "provides synchronous polling for legacy compatibility" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        # Write 'a' to the pipe
        bytes = Bytes['a'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # poll_sync should return the event directly (bypasses channel)
        event = source.poll_sync(100)
        event.should be_a(Termisu::Event::Key)
        event.as(Termisu::Event::Key).char.should eq('a')
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns nil on timeout" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)

        # No data written, should timeout
        event = source.poll_sync(10)
        event.should be_nil
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "restart lifecycle" do
    it "can be started again after stopping" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        # First start/stop cycle
        source.start(channel)
        source.running?.should be_true
        source.stop
        source.running?.should be_false

        # Second start should work with new channel
        channel2 = Channel(Termisu::Event::Any).new(10)
        source.start(channel2)
        source.running?.should be_true

        # Verify it still processes input after restart
        bytes = Bytes['x'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        select
        when event = channel2.receive
          event.should be_a(Termisu::Event::Key)
          event.as(Termisu::Event::Key).char.should eq('x')
        when timeout(100.milliseconds)
          fail "Timeout waiting for key event after restart"
        end

        source.stop
        channel.close
        channel2.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "Channel::ClosedError handling" do
    it "handles closed channel gracefully" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(1)

        source.start(channel)
        Fiber.yield # Let fiber start

        # Write data and close channel while source is running
        bytes = Bytes['a'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        sleep 20.milliseconds
        channel.close
        source.stop

        # Should have stopped without raising
        source.running?.should be_false
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "thread safety" do
    it "uses Atomic for running state" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)
        source = Termisu::Event::Source::Input.new(reader, parser)
        channel = Channel(Termisu::Event::Any).new(10)

        # Start and stop from different contexts should be safe
        spawn do
          source.start(channel)
          sleep 10.milliseconds
          source.stop
        end

        sleep 5.milliseconds
        source.running?.should be_true

        sleep 20.milliseconds
        source.running?.should be_false

        channel.close
      ensure
        reader.try(&.close)
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end
end
