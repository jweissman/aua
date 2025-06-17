# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Data Types Features" do
  describe "primitive literals" do
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

    it "recognizes negative floating point literals" do
      result = Aua.run("-3.14")
      expect(result).to be_a(Aua::Float)
      expect(result.value).to eq(-3.14)
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

    it "recognizes string with spaces" do
      result = Aua.run('"hello world"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("hello world")
    end

    it "recognizes nil literal" do
      result = Aua.run("nihil")
      expect(result).to be_a(Aua::Nihil)
      expect(result.value).to be_nil
    end
  end

  describe "expression parsing" do
    it "recognizes parenthesized expressions" do
      result = Aua.run("(123)")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end

    it "handles multiple and nested parentheses" do
      result = Aua.run("((123))")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end

    it "ignores leading and trailing whitespace" do
      result = Aua.run("   42   ")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(42)
    end
  end

  describe "error handling" do
    it "raises an error for parsing problems" do
      expect { Aua.run("123abc") }.to raise_error(Aua::Error)
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

    it "raises on unbalanced parentheses" do
      expect { Aua.run("(1 + 2") }.to raise_error(Aua::Error, /Unmatched opening parenthesis/)
    end

    it "raises on unterminated string" do
      expect { Aua.run('"unterminated string') }.to raise_error(Aua::Error, /Unterminated string literal/)
    end
  end
end
