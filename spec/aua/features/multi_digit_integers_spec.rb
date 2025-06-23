# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Multi-Character Integer Literals" do
  context "basic multi-digit integers" do
    it "parses single digit integers" do
      expect("5").to be_aua(5).and_be_a(Aua::Int)
    end

    it "parses two-digit integers" do
      expect("42").to be_aua(42).and_be_a(Aua::Int)
    end

    it "parses three-digit integers" do
      expect("123").to be_aua(123).and_be_a(Aua::Int)
    end

    it "parses larger integers" do
      expect("1000").to be_aua(1000).and_be_a(Aua::Int)
    end
  end

  context "integers in expressions" do
    it "adds multi-digit integers" do
      expect("10 + 20").to be_aua(30).and_be_a(Aua::Int)
    end

    it "compares multi-digit integers" do
      expect("85 == 85").to be_aua(true).and_be_a(Aua::Bool)
      expect("85 == 90").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "uses comparison operators with multi-digit integers" do
      expect("85 > 80").to be_aua(true).and_be_a(Aua::Bool)
      expect("85 < 90").to be_aua(true).and_be_a(Aua::Bool)
      expect("85 >= 85").to be_aua(true).and_be_a(Aua::Bool)
      expect("80 <= 85").to be_aua(true).and_be_a(Aua::Bool)
    end
  end

  context "integers in variables" do
    it "assigns and retrieves multi-digit integers" do
      expect("score = 85; score").to be_aua(85).and_be_a(Aua::Int)
    end

    it "compares variables with multi-digit integers" do
      expect("age = 25; age >= 18").to be_aua(true).and_be_a(Aua::Bool)
    end
  end
end
