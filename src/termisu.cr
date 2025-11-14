class Termisu
  VERSION = "0.0.1.alpha"

  def initialize : Int32
    0
  end

  def shutdown : Nil
  end

  def width : Int32
    0
  end

  def height : Int32
    0
  end

  def clear : Nil
  end

  def present : Nil
  end

  def put_cell(x : Int32, y : Int32, cell : Termisu::Cell) : Nil
  end

  def change_cell(x : Int32, y : Int32, ch : UInt32, fg : UInt16, bg : UInt16) : Nil
  end

  def blit(x : Int32, y : Int32, h : Int32, cell : Termisu::Cell) : Nil
  end

  def select_input_mode(mode : Termisu::InputMode) : Bool
  end

  def peek_event(event : Termisu::Event, timeout : Int32) : Int32
  end

  def poll_event(event : Termisu::Event) : Int32
  end
end

require "./termisu/*"
