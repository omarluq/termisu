require "../../spec_helper"

describe Termisu::Terminfo::Tparm do
  describe ".process" do
    describe "literal output" do
      it "returns literal characters unchanged" do
        Termisu::Terminfo::Tparm.process("hello").should eq("hello")
      end

      it "handles empty string" do
        Termisu::Terminfo::Tparm.process("").should eq("")
      end

      it "outputs literal percent with %%" do
        Termisu::Terminfo::Tparm.process("100%%").should eq("100%")
      end

      it "preserves escape sequences" do
        Termisu::Terminfo::Tparm.process("\e[H").should eq("\e[H")
      end
    end

    describe "parameter operations (%p1-%p9)" do
      it "pushes and outputs first parameter" do
        Termisu::Terminfo::Tparm.process("%p1%d", 42).should eq("42")
      end

      it "pushes and outputs second parameter" do
        Termisu::Terminfo::Tparm.process("%p2%d", 10, 20).should eq("20")
      end

      it "handles multiple parameters" do
        Termisu::Terminfo::Tparm.process("%p1%d;%p2%d", 5, 10).should eq("5;10")
      end

      it "returns 0 for missing parameter" do
        Termisu::Terminfo::Tparm.process("%p3%d", 1, 2).should eq("0")
      end

      it "handles all 9 parameters" do
        result = Termisu::Terminfo::Tparm.process(
          "%p1%d%p2%d%p3%d%p4%d%p5%d%p6%d%p7%d%p8%d%p9%d",
          1, 2, 3, 4, 5, 6, 7, 8, 9
        )
        result.should eq("123456789")
      end
    end

    describe "output formats" do
      it "outputs decimal with %d" do
        Termisu::Terminfo::Tparm.process("%p1%d", 123).should eq("123")
      end

      it "outputs string with %s" do
        Termisu::Terminfo::Tparm.process("%p1%s", 456).should eq("456")
      end

      it "outputs character with %c" do
        Termisu::Terminfo::Tparm.process("%p1%c", 65).should eq("A")
      end

      it "handles zero with %d" do
        Termisu::Terminfo::Tparm.process("%p1%d", 0).should eq("0")
      end

      it "handles negative numbers with %d" do
        Termisu::Terminfo::Tparm.process("%p1%d", -5).should eq("-5")
      end
    end

    describe "constants" do
      it "pushes integer constant with %{n}" do
        Termisu::Terminfo::Tparm.process("%{42}%d").should eq("42")
      end

      it "pushes character constant with %'c'" do
        Termisu::Terminfo::Tparm.process("%'A'%d").should eq("65")
      end

      it "handles multi-digit integer constants" do
        Termisu::Terminfo::Tparm.process("%{123}%d").should eq("123")
      end
    end

    describe "%i increment operation" do
      it "increments first two parameters" do
        Termisu::Terminfo::Tparm.process("%i%p1%d;%p2%d", 0, 0).should eq("1;1")
      end

      it "increments only first param when only one provided" do
        Termisu::Terminfo::Tparm.process("%i%p1%d", 5).should eq("6")
      end

      it "works with cup capability format" do
        # Standard cup: \e[%i%p1%d;%p2%dH
        result = Termisu::Terminfo::Tparm.process("\e[%i%p1%d;%p2%dH", 0, 0)
        result.should eq("\e[1;1H")
      end

      it "converts 0-based to 1-based coordinates" do
        result = Termisu::Terminfo::Tparm.process("\e[%i%p1%d;%p2%dH", 4, 9)
        result.should eq("\e[5;10H")
      end
    end

    describe "arithmetic operations" do
      it "adds with %+" do
        Termisu::Terminfo::Tparm.process("%p1%p2%+%d", 3, 5).should eq("8")
      end

      it "subtracts with %-" do
        Termisu::Terminfo::Tparm.process("%p1%p2%-%d", 10, 3).should eq("7")
      end

      it "multiplies with %*" do
        Termisu::Terminfo::Tparm.process("%p1%p2%*%d", 4, 5).should eq("20")
      end

      it "divides with %/" do
        Termisu::Terminfo::Tparm.process("%p1%p2%/%d", 20, 4).should eq("5")
      end

      it "handles division by zero gracefully" do
        Termisu::Terminfo::Tparm.process("%p1%p2%/%d", 10, 0).should eq("0")
      end

      it "calculates modulo with %m" do
        Termisu::Terminfo::Tparm.process("%p1%p2%m%d", 17, 5).should eq("2")
      end

      it "handles modulo by zero gracefully" do
        Termisu::Terminfo::Tparm.process("%p1%p2%m%d", 10, 0).should eq("0")
      end
    end

    describe "bitwise operations" do
      it "performs AND with %&" do
        Termisu::Terminfo::Tparm.process("%p1%p2%&%d", 0b1100, 0b1010).should eq("8")
      end

      it "performs OR with %|" do
        Termisu::Terminfo::Tparm.process("%p1%p2%|%d", 0b1100, 0b1010).should eq("14")
      end

      it "performs XOR with %^" do
        Termisu::Terminfo::Tparm.process("%p1%p2%^%d", 0b1100, 0b1010).should eq("6")
      end

      it "performs bitwise complement with %~" do
        # ~0 should be -1 in two's complement
        Termisu::Terminfo::Tparm.process("%p1%~%d", 0).should eq("-1")
      end
    end

    describe "comparison operations" do
      it "tests equality with %=" do
        Termisu::Terminfo::Tparm.process("%p1%p2%=%d", 5, 5).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%=%d", 5, 3).should eq("0")
      end

      it "tests less than with %<" do
        Termisu::Terminfo::Tparm.process("%p1%p2%<%d", 3, 5).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%<%d", 5, 3).should eq("0")
      end

      it "tests greater than with %>" do
        Termisu::Terminfo::Tparm.process("%p1%p2%>%d", 5, 3).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%>%d", 3, 5).should eq("0")
      end
    end

    describe "logical operations" do
      it "performs logical AND with %A" do
        Termisu::Terminfo::Tparm.process("%p1%p2%A%d", 1, 1).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%A%d", 1, 0).should eq("0")
        Termisu::Terminfo::Tparm.process("%p1%p2%A%d", 0, 1).should eq("0")
        Termisu::Terminfo::Tparm.process("%p1%p2%A%d", 0, 0).should eq("0")
      end

      it "performs logical OR with %O" do
        Termisu::Terminfo::Tparm.process("%p1%p2%O%d", 1, 1).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%O%d", 1, 0).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%O%d", 0, 1).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%p2%O%d", 0, 0).should eq("0")
      end

      it "performs logical NOT with %!" do
        Termisu::Terminfo::Tparm.process("%p1%!%d", 0).should eq("1")
        Termisu::Terminfo::Tparm.process("%p1%!%d", 1).should eq("0")
        Termisu::Terminfo::Tparm.process("%p1%!%d", 5).should eq("0")
      end
    end

    describe "string length with %l" do
      it "pushes string length" do
        # For terminfo, we convert number to string and get length
        Termisu::Terminfo::Tparm.process("%p1%l%d", 123).should eq("3")
        Termisu::Terminfo::Tparm.process("%p1%l%d", 12345).should eq("5")
      end
    end

    describe "variables" do
      it "stores and retrieves dynamic variables" do
        # Store in dynamic var 'a', retrieve it
        Termisu::Terminfo::Tparm.process("%p1%Pa%ga%d", 42).should eq("42")
      end

      it "handles multiple dynamic variables" do
        result = Termisu::Terminfo::Tparm.process("%p1%Pa%p2%Pb%ga%d%gb%d", 10, 20)
        result.should eq("1020")
      end

      it "stores and retrieves static variables" do
        # Store in static var 'A', retrieve it
        Termisu::Terminfo::Tparm.process("%p1%PA%gA%d", 99).should eq("99")
      end

      it "returns 0 for unset variables" do
        Termisu::Terminfo::Tparm.process("%gz%d").should eq("0")
      end
    end

    describe "conditional expressions (%? %t %e %;)" do
      it "evaluates then-part when condition is true" do
        result = Termisu::Terminfo::Tparm.process("%?%p1%tYES%;", 1)
        result.should eq("YES")
      end

      it "skips then-part when condition is false" do
        result = Termisu::Terminfo::Tparm.process("%?%p1%tYES%;", 0)
        result.should eq("")
      end

      it "evaluates else-part when condition is false" do
        result = Termisu::Terminfo::Tparm.process("%?%p1%tYES%eNO%;", 0)
        result.should eq("NO")
      end

      it "skips else-part when condition is true" do
        result = Termisu::Terminfo::Tparm.process("%?%p1%tYES%eNO%;", 1)
        result.should eq("YES")
      end

      it "handles simple nested structure" do
        # Simple test: if p1 then "A" else "B"
        format = "%?%p1%tA%eB%;"
        Termisu::Terminfo::Tparm.process(format, 1).should eq("A")
        Termisu::Terminfo::Tparm.process(format, 0).should eq("B")
      end
    end

    describe "real-world capability strings" do
      it "processes cup capability" do
        # Standard xterm cup: \e[%i%p1%d;%p2%dH
        cup = "\e[%i%p1%d;%p2%dH"
        Termisu::Terminfo::Tparm.process(cup, 0, 0).should eq("\e[1;1H")
        Termisu::Terminfo::Tparm.process(cup, 9, 19).should eq("\e[10;20H")
        Termisu::Terminfo::Tparm.process(cup, 23, 79).should eq("\e[24;80H")
      end

      it "processes setaf (256-color foreground)" do
        # setaf: \e[38;5;%p1%dm
        setaf = "\e[38;5;%p1%dm"
        Termisu::Terminfo::Tparm.process(setaf, 1).should eq("\e[38;5;1m")
        Termisu::Terminfo::Tparm.process(setaf, 196).should eq("\e[38;5;196m")
      end

      it "processes setab (256-color background)" do
        # setab: \e[48;5;%p1%dm
        setab = "\e[48;5;%p1%dm"
        Termisu::Terminfo::Tparm.process(setab, 0).should eq("\e[48;5;0m")
        Termisu::Terminfo::Tparm.process(setab, 255).should eq("\e[48;5;255m")
      end

      it "processes cub (cursor backward)" do
        # cub: \e[%p1%dD
        cub = "\e[%p1%dD"
        Termisu::Terminfo::Tparm.process(cub, 5).should eq("\e[5D")
      end

      it "processes cuf (cursor forward)" do
        # cuf: \e[%p1%dC
        cuf = "\e[%p1%dC"
        Termisu::Terminfo::Tparm.process(cuf, 10).should eq("\e[10C")
      end

      it "processes cuu (cursor up)" do
        # cuu: \e[%p1%dA
        cuu = "\e[%p1%dA"
        Termisu::Terminfo::Tparm.process(cuu, 3).should eq("\e[3A")
      end

      it "processes cud (cursor down)" do
        # cud: \e[%p1%dB
        cud = "\e[%p1%dB"
        Termisu::Terminfo::Tparm.process(cud, 7).should eq("\e[7B")
      end
    end

    describe "edge cases" do
      it "handles empty stack gracefully" do
        # Pop from empty stack should return 0
        Termisu::Terminfo::Tparm.process("%d").should eq("0")
      end

      it "handles trailing % without operation" do
        # Should handle gracefully
        Termisu::Terminfo::Tparm.process("test%").should eq("test")
      end

      it "handles very large numbers" do
        Termisu::Terminfo::Tparm.process("%p1%d", Int64::MAX).should eq(Int64::MAX.to_s)
      end

      it "handles negative parameters" do
        Termisu::Terminfo::Tparm.process("%p1%d", -100).should eq("-100")
      end
    end
  end
end
