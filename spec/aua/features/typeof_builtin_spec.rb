# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "typeof built-in function" do
  context "basic types" do
    it "returns 'Int' for integers" do
      expect("typeof 42").to be_aua("Int").and_be_a(Aua::Str)
    end

    it "returns 'Str' for strings" do
      expect('typeof "hello"').to be_aua("Str").and_be_a(Aua::Str)
    end

    it "returns 'Bool' for booleans" do
      expect("typeof true").to be_aua("Bool").and_be_a(Aua::Str)
      expect("typeof false").to be_aua("Bool").and_be_a(Aua::Str)
    end

    it "returns 'Float' for floating point numbers" do
      expect("typeof 3.14").to be_aua("Float").and_be_a(Aua::Str)
    end

    it "returns 'Nihil' for nihil" do
      expect("typeof nihil").to be_aua("Nihil").and_be_a(Aua::Str)
    end
  end

  context "collection types" do
    it "returns 'List' for arrays" do
      expect("typeof([1, 2, 3])").to be_aua("List").and_be_a(Aua::Str)
    end

    it "returns 'Object' for object literals" do
      expect("typeof { name: 'Alice', age: 30 }").to be_aua("Object").and_be_a(Aua::Str)
    end
  end

  context "function types" do
    it "returns 'Function' for lambda expressions" do
      expect("typeof (x => x * 2)").to be_aua("Function").and_be_a(Aua::Str)
    end

    it "returns 'Function' for named functions" do
      expect("fun add(x, y) x + y end; typeof add").to be_aua("Function").and_be_a(Aua::Str)
    end
  end

  context "usage in expressions" do
    it "can be used in conditionals" do
      result = Aua.run(<<~AURA)
        x = 42
        if typeof(x) == "Int"
          "is integer"
        else
          "not integer"
        end
      AURA
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("is integer")
    end

    it "can be used with variables" do
      result = Aua.run(<<~AURA)
        data = [1, 2, 3]
        type_name = typeof data
        type_name
      AURA
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("List")
    end
  end

  context "error handling" do
    it "raises an error when called with no arguments" do
      expect("typeof").to raise_aura(/Undefined/)
    end

    it "raises an error when called with multiple arguments" do
      expect("typeof(1, 2)").to raise_aura(/Wrong number of arguments/)
    end
  end
end
