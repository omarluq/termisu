require "./spec_helper"

describe Termisu do
  it "has a version number" do
    Termisu::VERSION.should_not be_nil
  end

  describe ".new" do
    it "initializes or raises IO::Error without /dev/tty" do
      begin
        termisu = Termisu.new
        termisu.should be_a(Termisu)
        termisu.close
      rescue ex : IO::Error
        ex.message.should_not be_nil
      end
    end
  end
end
