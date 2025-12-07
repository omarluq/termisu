require "../spec_helper"

describe Termisu::Error do
  it "is an Exception" do
    error = Termisu::Error.new("test error")
    error.should be_a(Exception)
  end

  it "stores error message" do
    error = Termisu::Error.new("test error")
    error.message.should eq("test error")
  end
end

describe Termisu::IOError do
  it "is a Termisu::Error" do
    error = Termisu::IOError.new(Errno::EINTR, "test operation")
    error.should be_a(Termisu::Error)
  end

  it "stores errno value" do
    error = Termisu::IOError.new(Errno::EBADF, "test")
    error.errno.should eq(Errno::EBADF)
  end

  it "includes operation in message" do
    error = Termisu::IOError.new(Errno::EIO, "read()")
    message = error.message
    message.should_not be_nil
    message.should contain("read()") if message
  end

  describe ".select_failed" do
    it "creates error with select context" do
      error = Termisu::IOError.select_failed(Errno::EBADF)
      message = error.message
      message.should_not be_nil
      message.should contain("select()") if message
      error.errno.should eq(Errno::EBADF)
    end
  end

  describe ".read_failed" do
    it "creates error with read context" do
      error = Termisu::IOError.read_failed(Errno::EIO)
      message = error.message
      message.should_not be_nil
      message.should contain("read()") if message
      error.errno.should eq(Errno::EIO)
    end
  end

  describe "errno predicates" do
    it "can check for EINTR" do
      error = Termisu::IOError.new(Errno::EINTR, "test")
      error.errno.eintr?.should be_true
    end

    it "can check for EAGAIN" do
      error = Termisu::IOError.new(Errno::EAGAIN, "test")
      error.errno.eagain?.should be_true
    end

    it "can check for EBADF" do
      error = Termisu::IOError.new(Errno::EBADF, "test")
      error.errno.ebadf?.should be_true
    end
  end
end
