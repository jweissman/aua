# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Logical Operators" do
  context "logical AND (&&)" do
    it "returns true when both operands are true" do
      expect("true && true").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "returns false when left operand is false" do
      expect("false && true").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "returns false when right operand is false" do
      expect("true && false").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "returns false when both operands are false" do
      expect("false && false").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "works with variables" do
      expect("x = true; y = false; x && y").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "works with comparison expressions" do
      expect("5 > 3 && 2 < 4").to be_aua(true).and_be_a(Aua::Bool)
    end
  end

  context "logical OR (||)" do
    it "returns true when both operands are true" do
      expect("true || true").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "returns true when left operand is true" do
      expect("true || false").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "returns true when right operand is true" do
      expect("false || true").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "returns false when both operands are false" do
      expect("false || false").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "works with variables" do
      expect("x = false; y = true; x || y").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "works with comparison expressions" do
      expect("5 < 3 || 2 < 4").to be_aua(true).and_be_a(Aua::Bool)
    end
  end

  context "logical NOT (!)" do
    it "negates true to false" do
      expect("!true").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "negates false to true" do
      expect("!false").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "works with variables" do
      expect("x = true; !x").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "works with comparison expressions" do
      expect("!(5 > 3)").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  context "complex logical expressions" do
    it "handles precedence correctly" do
      expect("true && false || true").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "handles parentheses for grouping" do
      expect("true && (false || true)").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "combines with comparison operators" do
      expect("age = 25; hasLicense = true; age >= 18 && hasLicense").to be_aua(true).and_be_a(Aua::Bool)
    end
  end
end
