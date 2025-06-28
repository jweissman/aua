# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Boolean Value Processing" do
  context "basic boolean literals" do
    it "parses true literal" do
      expect("true").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "parses false literal" do
      expect("false").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  context "boolean variables" do
    it "assigns and retrieves true" do
      expect("x = true; x").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "assigns and retrieves false" do
      expect("x = false; x").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  context "boolean from comparisons" do
    it "produces true from equality" do
      expect("5 == 5").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "produces false from equality" do
      expect("5 == 3").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "produces true from greater than" do
      expect("5 > 3").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "produces false from greater than" do
      expect("3 > 5").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "produces true from less than" do
      expect("3 < 5").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "produces false from less than" do
      expect("5 < 3").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  context "boolean resolution and storage" do
    it "stores comparison result in variable correctly" do
      expect("result = (5 > 3); result").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "stores false comparison result correctly" do
      expect("result = (5 < 3); result").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "maintains boolean value through multiple operations" do
      expect("x = true; y = x; z = y; z").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "maintains false value through multiple operations" do
      expect("x = false; y = x; z = y; z").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  context "boolean in conditionals" do
    it "uses true boolean in ternary conditional" do
      expect("x = true; if x then \"yes\" else \"no\"").to be_aua("yes").and_be_a(Aua::Str)
    end

    it "uses false boolean in ternary conditional" do
      expect("x = false; if x then \"yes\" else \"no\"").to be_aua("no").and_be_a(Aua::Str)
    end

    it "uses comparison result in ternary conditional" do
      code = 'result = (5 > 3); if result then "greater" else "not greater"'
      expect(code).to be_aua("greater").and_be_a(Aua::Str)
    end
  end
end
