# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.tap { $stdout = original_stdout }
  end

  # define a helper method to run Aua code and return the result
  RSpec::Matchers.define :be_aua do |code|
    match do |actual, type: Aua::Obj|
      @result = Aua.run(code)
      @result.is_a?(type) && @result.value == actual
    end
    failure_message do
      "expected Aua to return #{actual.inspect}, but got #{@result.inspect}"
    end
    failure_message_when_negated do
      "expected Aua not to return #{actual.inspect}, but it did"
    end
    description do
      "run Aua code and return #{actual.inspect}"
    end
  end

  describe "Data Types" do
    it "returns an Int object for integer literals" do
      result = Aua.run("123")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end

    it "recognizes negative integers" do
      result = Aua.run("-42")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(-42)
    end

    it "recognizes floating point literals" do
      result = Aua.run("3.14")
      expect(result).to be_a(Aua::Float)
      expect(result.value).to eq(3.14)
    end

    it "recognizes boolean true literal" do
      result = Aua.run("true")
      expect(result).to be_a(Aua::Bool)
      expect(result.value).to eq(true)
    end

    it "recognizes boolean false literal" do
      result = Aua.run("false")
      expect(result).to be_a(Aua::Bool)
      expect(result.value).to eq(false)
    end

    it "recognizes string literals" do
      result = Aua.run('"hello"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("hello")
    end

    it "recognizes nil literal" do
      result = Aua.run("nihil")
      expect(result).to be_a(Aua::Nihil)
      expect(result.value).to be_nil
    end

    it "recognizes boolean literal" do
      result = Aua.run("true")
      expect(result).to be_a(Aua::Bool)
      expect(result.value).to eq(true)

      result = Aua.run("false")
      expect(result).to be_a(Aua::Bool)
      expect(result.value).to eq(false)
    end

    it "raises an error for parsing problems" do
      expect { Aua.run("123abc") }.to raise_error(Aua::Error)
    end

    it "recognizes parenthesized expressions" do
      result = Aua.run("(123)")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end

    it "ignores leading and trailing whitespace" do
      result = Aua.run("   42   ")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(42)
    end

    it "handles multiple and nested parentheses" do
      result = Aua.run("((123))")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end

    it "recognizes negative floating point literals" do
      result = Aua.run("-3.14")
      expect(result).to be_a(Aua::Float)
      expect(result.value).to eq(-3.14)
    end

    it "raises error for unary minus on boolean" do
      expect { Aua.run("-true") }.to raise_error(Aua::Error)
    end

    it "raises error for unary minus on string" do
      expect { Aua.run('-"hello"') }.to raise_error(Aua::Error)
    end

    it "raises error for unary minus on nihil" do
      expect { Aua.run("-nihil") }.to raise_error(Aua::Error)
    end

    it "raises error for empty input" do
      expect { Aua.run("") }.to raise_error(Aua::Error)
    end

    it "raises on unknown identifiers" do
      expect { Aua.run("foo") }.to raise_error(Aua::Error, /Undefined variable/)
    end

    it "recognizes string with spaces" do
      result = Aua.run('"hello world"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("hello world")
    end

    it "raises on unbalanced parentheses" do
      expect { Aua.run("(1 + 2") }.to raise_error(Aua::Error, /Unmatched opening parenthesis/)
    end

    it "raises on unterminated string" do
      expect { Aua.run('"unterminated string') }.to raise_error(Aua::Error, /Unterminated string literal/)
    end
  end

  describe "Assignments" do
    it "assigns values to variables" do
      result = Aua.run("x = 42")
      expect(result).to be_a(Aua::Obj)
      expect(result.value).to eq(42)
    end

    it "updates variable values" do
      first_result = Aua.run("x = 42")
      expect(first_result).to be_a(Aua::Obj)
      expect(first_result.value).to eq(42)

      result = Aua.run("x = 100")
      expect(result).to be_a(Aua::Obj)
      expect(result.value).to eq(100)
    end

    it "assigns strings to variables" do
      result = Aua.run('name = "Alice"')
      expect(result).to be_a(Aua::Obj)
      expect(result.value).to eq("Alice")
    end
  end

  describe "Binary Operations" do
    describe "Basic Arithmetic" do
      it "adds two integers" do
        result = Aua.run("1 + 2")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(3)
      end

      it "subtracts two integers" do
        result = Aua.run("5 - 3")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(2)
      end

      it "multiplies two integers" do
        result = Aua.run("4 * 2")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(8)
      end

      it "divides two integers" do
        result = Aua.run("8 / 2")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(4)
      end

      it "raises error for division by zero" do
        expect { Aua.run("1 / 0") }.to raise_error(Aua::Error)
      end

      it "adds two floats" do
        result = Aua.run("1.5 + 2.5")
        expect(result).to be_a(Aua::Float)
        expect(result.value).to eq(4.0)
      end

      it "subtracts two floats" do
        result = Aua.run("5.5 - 3.5")
        expect(result).to be_a(Aua::Float)
        expect(result.value).to eq(2.0)
      end

      it "multiplies two floats" do
        result = Aua.run("4.0 * 2.0")
        expect(result).to be_a(Aua::Float)
        expect(result.value).to eq(8.0)
      end

      it "divides two floats" do
        result = Aua.run("8.0 / 2.0")
        expect(result).to be_a(Aua::Float)
        expect(result.value).to eq(4.0)
      end

      it "concatenates two strings" do
        result = Aua.run('"hello" + " world"')
        expect(result).to be_a(Aua::Str)
        expect(result.value).to eq("hello world")
      end

      it "raises error for unsupported operations on different types" do
        # NOTE: this now passes due to bool => 1 : 0 conversion
        # expect { Aua.run("1 + true") }.to raise_error(Aua::Error)
        expect { Aua.run('"hello" + 42') }.to raise_error(Aua::Error)
        expect { Aua.run("true + false") }.to raise_error(Aua::Error)
      end

      it "exponentiates two integers" do
        result = Aua.run("2 ** 3")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(8)
      end

      it "exponentiates two floats" do
        result = Aua.run("0.2 ** 3.14159265")
        expect(result).to be_a(Aua::Float)
        expect(result.value).to eq(0.2**3.14159265)
      end
    end

    describe "Operations with Variables" do
      it "adds variables" do
        Aua.run("x = 5")
        result = Aua.run("x + 3")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(8)
      end
      it "subtracts variables" do
        Aua.run("x = 10")
        result = Aua.run("x - 4")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(6)
      end
      it "multiplies variables" do
        Aua.run("x = 7")
        result = Aua.run("x * 2")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(14)
      end
      it "divides variables" do
        Aua.run("x = 20")
        result = Aua.run("x / 4")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(5)
      end
    end

    describe "Operator Precedence" do
      it "right-associates exponentiation" do
        result = Aua.run("2 ** 3 ** 2")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(512)
      end

      it "handles mixed operations with correct precedence" do
        result = Aua.run("2 + 3 * 4 - 5 / 5")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(13)

        result = Aua.run("10 - 2 ** 3 + 1")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(3)
      end

      it "handles parentheses correctly" do
        result = Aua.run("(1 + 2) * 3")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(9)

        result = Aua.run("2 * (3 + 4)")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(14)
      end
    end
  end

  describe "Strings" do
    it "concatenates strings with +" do
      result = Aua.run('"Hello, " + "world!"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hello, world!")
    end

    it "interpolates variables in strings" do
      Aua.run('name = "Alice"')
      result = Aua.run('"Hello, ${name}!"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hello, Alice!")
    end

    it "interpolates multiple variables in strings" do
      Aua.run("x = 5; y = 10")
      result = Aua.run('"The values are ${x} and ${y}"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("The values are 5 and 10")
    end
  end

  describe "Control Flow" do
    it "conditional execution with if-else" do
      result = Aua.run("if true then 1 else 2")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(1)

      result = Aua.run("if false then 1 else 2")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(2)
    end
  end

  describe "Generative String Literals", gen: true do
    it "evaluates a generative string literal and returns a string containing Rayleigh" do
      # result = Aua.run('"""Why is the sky blue?"""')
      result = Aua.run('"""What is the name of the physical phenomena responsible for the sky being blue?"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to match(/Rayleigh/i)
    end

    it "interpolates variables in generative strings" do
      result = Aua.run('name = "Alice"; """Please write a short story about ${name}"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Alice")
    end
  end

  describe "Universal Generative Typecasting" do
    it "generates an appropriate string/bool representation for various types", skip: true do
      expect(Aua.run("1 as Word").to_s).to eq("'one'")
      expect(Aua.run("3.14 as Word").to_s).to eq("'pi'")
      expect(Aua.run("true as 'yes' | 'no'").to_s).to eq("'yes'")
      expect(Aua.run('"ok" as Bool').to_s).to eq("false")
      expect(Aua.run("nihil as String").to_s).to eq("'nothing'")
    end
  end

  describe "Built-in Functions" do
    describe "Time and Date Functions" do
      it "returns the current time" do
        result = Aua.run("time 'now'")
        expect(result).to be_a(Aua::Time)
        expect(result.value).to be_within(1).of(Time.now)
      end
    end

    describe "Random Number Generation" do
      it "generates a random integer within a range" do
        result = Aua.run("rand(10)")
        expect(result).to be_a(Aua::Int)
        expect(result.value).to be_between(0, 10).inclusive
      end
    end

    describe "STDOUT" do
      it "prints to standard output with single-quoted str" do
        stdout = with_captured_stdout { Aua.run("say 'hi'") }
        expect(stdout).to include("hi")
      end

      # NOTE: This test is failing.
      it "prints to standard output with double-quoted str" do
        stdout = with_captured_stdout { Aua.run('say "hello world"') }
        expect(stdout).to include("hello world")
      end

      it "prints to standard output with generative string" do
        stdout = with_captured_stdout { Aua.run('say """hello world"""') }
        expect(stdout).to include("How can I")
      end
    end
  end

  describe "Complex Expressions" do
    context "with multiple instructions" do
      let(:input) { "x = 5; y = x + 2\ny * 3" }
      it "evaluates multiple instructions and returns the last result" do
        result = Aua.run(input)
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(21)
      end
    end

    context "with nested expressions" do
      let(:input) { "x = (1 + 2) * 3; y = x - 4; z = y * 2; x + y + z" }
      it "evaluates nested expressions correctly" do
        result = Aua.run(input)
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(24)
      end
    end
  end

  context "with multiple commands" do
    let(:input) do
      <<~AURA
        x = 5
        y = x + 2
        say "The result is: ${y}"
      AURA
    end

    it "evaluates multiple commands and returns the last result" do
      stdout = with_captured_stdout { Aua.run(input) }
      expect(stdout).to include("The result is: 7")
    end
  end

  context "with realistic shebang" do
    let(:input) { "#!/usr/bin/env aura\nx = 42\nx + 1" }
    it "runs the script with shebang and returns the result" do
      result = Aua.run(input)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(43)
    end
  end
end
