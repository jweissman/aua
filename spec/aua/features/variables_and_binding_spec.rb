# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Variables and Binding Features" do
  describe "basic assignment" do
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

  describe "operations with variables" do
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

  describe "complex expressions with variables" do
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
end
