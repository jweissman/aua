# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua do
  before { Aua.testing = true }

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
      result = Aua.run("x = 100")
      expect(result).to be_a(Aua::Obj)
      expect(result.value).to eq(100)
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
        expect { Aua.run("1 + true") }.to raise_error(Aua::Error)
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

  describe "Control Flow" do
    it 'conditional execution with if-else' do
      result = Aua.run('if true then 1 else 2 end')
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(1)

      result = Aua.run('if false then 1 else 2 end')
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(2)
    end
  end

  describe "Generative String Literals" do
    it "evaluates a generative string literal and returns a string containing Rayleigh" do
      # result = Aua.run('"""Why is the sky blue?"""')
      result = Aua.run('"""What is the name of the physical phenomena responsible for the sky being blue?"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to match(/Rayleigh/i)
    end
  end
end
