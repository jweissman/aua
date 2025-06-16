# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Aura typedef/type system", skip: true do
  it "allows defining and using a simple enum type" do
    code = <<~AUA
      type YesNo = 'yes' | 'no'
      result = true as YesNo
      result
    AUA
    result = Aua.run(code)
    expect(result).to be_a(Aua::Str)
    expect(result.value).to eq("yes")
  end

  it "allows defining and using a record/interface type" do
    code = <<~AUA
      type Point = { x: Int, y: Int }
      result = { x: 3, y: 4 } as Point
      result.x + result.y
    AUA
    result = Aua.run(code)
    expect(result).to be_a(Aua::Int)
    expect(result.value).to eq(7)
  end

  it "allows casting to a union of primitives" do
    code = <<~AUA
      type NumOrStr = Int | Str
      result = 42 as NumOrStr
      result
    AUA
    result = Aua.run(code)
    expect([Aua::Int, Aua::Str]).to include(result.class)
    expect([42, "42"]).to include(result.value)
  end
end
