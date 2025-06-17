# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Operations Features" do
  describe "basic arithmetic" do
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

    it "exponentiates two integers" do
      result = Aua.run("2 ** 3")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(8)
    end

    it "raises error for division by zero" do
      expect { Aua.run("1 / 0") }.to raise_error(Aua::Error)
    end
  end

  describe "floating point arithmetic" do
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

    it "exponentiates two floats" do
      result = Aua.run("0.2 ** 3.14159265")
      expect(result).to be_a(Aua::Float)
      expect(result.value).to eq(0.2**3.14159265)
    end
  end

  describe "string operations" do
    it "concatenates two strings" do
      result = Aua.run('"hello" + " world"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("hello world")
    end

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

  describe "operator precedence" do
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

  describe "type operation errors" do
    it "raises error for unsupported operations on different types" do
      # NOTE: this now passes due to bool => 1 : 0 conversion
      # expect { Aua.run("1 + true") }.to raise_error(Aua::Error)
      expect { Aua.run('"hello" + 42') }.to raise_error(Aua::Error)
      expect { Aua.run("true + false") }.to raise_error(Aua::Error)
    end
  end
end
