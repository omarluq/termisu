require "../spec_helper"

describe Termisu::Cursor do
  it "can be instantiated" do
    cursor = Termisu::Cursor.new
    cursor.should be_a(Termisu::Cursor)
  end
end
