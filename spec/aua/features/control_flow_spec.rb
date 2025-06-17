# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Control Flow Features" do
  describe "conditional expressions" do
    it "evaluates if-else with true condition" do
      result = Aua.run("if true then 1 else 2")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(1)
    end

    it "evaluates if-else with false condition" do
      result = Aua.run("if false then 1 else 2")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(2)
    end
  end
end
