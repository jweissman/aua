# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Type System Features" do
  describe "record types" do
    it "can define and use a record type" do
      code = <<~AUA
        type Point = { x: Int, y: Int }
        Point
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("Point")
    end

    it "can create object literals" do
      code = "{ x: 3, y: 4 }"

      result = Aua.run(code)
      expect(result).to be_a(Aua::ObjectLiteral)
      expect(result.values["x"].value).to eq(3)
      expect(result.values["y"].value).to eq(4)
    end

    it "can parse record types with multiline syntax" do
      code = <<~AUA
        type Character = {
          name: Str,
          level: Int,
          items: List
        }
        Character
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("Character")
    end

    it "can create object literals with multiline syntax" do
      code = <<~AUA
        obj = {
          name: "Hero",
          level: 5,
          items: ["sword", "shield"]
        }
        obj.name
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hero")
    end

    it "can access object fields" do
      code = <<~AUA
        obj = { x: 3, y: 4 }
        obj.x
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(3)
    end
  end

  describe "union types" do
    it "can declare and lookup union types" do
      code = <<~AUA
        type YesNo = 'yes' | 'no'
        YesNo
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("YesNo")
      expect(result.union_values).to eq(%w[yes no])
    end
  end

  describe "list types" do
    it "can declare and use list types without generics" do
      code = <<~AUA
        type ItemList = List
        items = ItemList
        items
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("ItemList")
    end

    it "can parse record types with list fields" do
      code = <<~AUA
        type Character = {
          name: Str,
          level: Int,
          items: List
        }
        Character
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("Character")
    end

    it "can create and parse array literals" do
      code = '["sword", "bow", "shield"]'

      result = Aua.run(code)
      expect(result).to be_a(Aua::List)
      expect(result.values.length).to eq(3)
      expect(result.values[0].value).to eq("sword")
      expect(result.values[1].value).to eq("bow")
      expect(result.values[2].value).to eq("shield")
    end

    it "can create array literals with multiline syntax" do
      code = <<~AUA
        items = [
          "sword",
          "bow",
          "shield"
        ]
        items
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::List)
      expect(result.values.length).to eq(3)
      expect(result.values[0].value).to eq("sword")
    end

    it "can use array literals in object literals" do
      code = <<~AUA
        character = {
          name: "Hero",
          items: ["sword", "bow"]
        }
        character.items
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::List)
      expect(result.values.length).to eq(2)
      expect(result.values[0].value).to eq("sword")
      expect(result.values[1].value).to eq("bow")
    end
  end
end
