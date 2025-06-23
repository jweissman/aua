# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Conditional Control Flow Features" do
  context "multi-block conditionals" do
    context "if/end blocks" do
      it "executes simple if block when condition is true" do
        code = <<~AURA
          x = 5
          result = "default"
          if x == 5
            result = "match"
          end
          result
        AURA
        expect(code).to be_aua("match").and_be_a(Aua::Str)
      end

      it "skips if block when condition is false" do
        code = <<~AURA
          x = 3
          result = "default"
          if x == 5
            result = "match"
          end
          result
        AURA
        expect(code).to be_aua("default").and_be_a(Aua::Str)
      end
    end

    context "if/else/end blocks" do
      it "executes if block when condition is true" do
        code = <<~AURA
          x = 5
          if x == 5
            result = "if branch"
          else
            result = "else branch"
          end
          result
        AURA
        expect(code).to be_aua("if branch").and_be_a(Aua::Str)
      end

      it "executes else block when condition is false" do
        code = <<~AURA
          x = 3
          if x == 5
            result = "if branch"
          else
            result = "else branch"
          end
          result
        AURA
        expect(code).to be_aua("else branch").and_be_a(Aua::Str)
      end
    end

    context "if/elif/else/end blocks" do
      it "executes first matching condition" do
        code = <<~AURA
          score = 85
          if score >= 90
            grade = "A"
          elif score >= 80
            grade = "B"
          elif score >= 70
            grade = "C"
          else
            grade = "F"
          end
          grade
        AURA
        expect(code).to be_aua("B").and_be_a(Aua::Str)
      end

      it "executes elif when if condition is false" do
        code = <<~AURA
          score = 75
          if score >= 90
            grade = "A"
          elif score >= 70
            grade = "C"
          else
            grade = "F"
          end
          grade
        AURA
        expect(code).to be_aua("C").and_be_a(Aua::Str)
      end

      it "executes else when all conditions are false" do
        code = <<~AURA
          score = 50
          if score >= 90
            grade = "A"
          elif score >= 80
            grade = "B"
          elif score >= 70
            grade = "C"
          else
            grade = "F"
          end
          grade
        AURA
        expect(code).to be_aua("F").and_be_a(Aua::Str)
      end
    end

    context "nested conditionals" do
      it "handles nested if/else blocks" do
        code = <<~AURA
          x = 5
          y = 10
          if x == 5
            if y == 10
              result = "both match"
            else
              result = "only x matches"
            end
          else
            result = "x doesn't match"
          end
          result
        AURA
        expect(code).to be_aua("both match").and_be_a(Aua::Str)
      end
    end

    context "conditionals with complex expressions" do
      it "handles multiple conditions with logical operators" do
        code = <<~AURA
          age = 25
          hasLicense = true
          if age >= 18 && hasLicense
            status = "can drive"
          else
            status = "cannot drive"
          end
          status
        AURA
        expect(code).to be_aua("can drive").and_be_a(Aua::Str)
      end
    end

    context "conditionals with return values" do
      it "returns value from executed branch" do
        code = <<~AURA
          x = 5
          result = if x == 5
            "match"
          else
            "no match"
          end
          result
        AURA
        expect(code).to be_aua("match").and_be_a(Aua::Str)
      end
    end
  end
end
