# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Record Types E2E" do
  describe "basic record type functionality" do
    it "can define and use a record type" do
      code = <<~AUA
        type Point = { x: Int, y: Int }
        Point
      AUA

      # This should work - just defining the type and referencing it
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

  describe "record type casting" do
    it "can cast object literals to record types", :llm_required do
      code = <<~AUA
        type Point = { x: Int, y: Int }
        result = { x: 3, y: 4 } as Point
        result
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::RecordObject)
      expect(result.type_name).to eq("Point")
      expect(result.values["x"]).to be_a(Aua::Int)
      expect(result.values["y"]).to be_a(Aua::Int)
    end

    it "can cast and access fields", :llm_required do
      code = <<~AUA
        type Point = { x: Int, y: Int }
        point = { x: 3, y: 4 } as Point
        point.x + point.y
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(7)
    end

    it "can cast from unstructured data to record types", :llm_required do
      code = <<~AUA
        type Point = { x: Int, y: Int }
        result = "coordinates: 3, 4" as Point
        result.x
      AUA

      # This tests the LLM's ability to extract structured data from text
      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(3)
    end
  end
end
