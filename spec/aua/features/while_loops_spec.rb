# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "While Loop Features" do
  context "basic while loops" do
    it "executes a simple counting loop" do
      code = <<~AURA
        counter = 0
        while counter < 3
          counter = counter + 1
        end
        counter
      AURA
      expect(code).to be_aua(3).and_be_a(Aua::Int)
    end

    it "handles loop with no iterations when condition is false" do
      code = <<~AURA
        x = 5
        while x < 3
          x = x + 1
        end
        x
      AURA
      expect(code).to be_aua(5).and_be_a(Aua::Int)
    end

    it "accumulates values in a loop" do
      code = <<~AURA
        sum = 0
        i = 1
        while i <= 4
          sum = sum + i
          i = i + 1
        end
        sum
      AURA
      expect(code).to be_aua(10).and_be_a(Aua::Int) # 1+2+3+4 = 10
    end
  end

  context "while loops with multiple statements" do
    it "executes multiple statements in loop body" do
      code = <<~AURA
        total = 0
        count = 0
        i = 1
        while i <= 3
          total = total + i
          count = count + 1
          i = i + 1
        end
        total
      AURA
      expect(code).to be_aua(6).and_be_a(Aua::Int) # 1+2+3 = 6
    end

    it "handles complex expressions in condition" do
      code = <<~AURA
        x = 1
        while x < 10 && x != 5
          x = x + 1
        end
        x
      AURA
      expect(code).to be_aua(5).and_be_a(Aua::Int)
    end
  end

  context "while loops with conditionals" do
    it "handles if statements inside while loops" do
      code = <<~AURA
        result = 0
        i = 1
        while i <= 5
          if i == 3
            result = result + 10
          else
            result = result + 1
          end
          i = i + 1
        end
        result
      AURA
      expect(code).to be_aua(14).and_be_a(Aua::Int) # 1+1+10+1+1 = 14
    end
  end

  context "nested while loops" do
    it "handles nested while loops" do
      code = <<~AURA
        total = 0
        i = 1
        while i <= 2
          j = 1
          while j <= 3
            total = total + 1
            j = j + 1
          end
          i = i + 1
        end
        total
      AURA
      expect(code).to be_aua(6).and_be_a(Aua::Int) # 2 * 3 = 6 iterations
    end
  end

  context "while loops with string operations" do
    it "handles string building in loops" do
      code = <<~AURA
        result = ""
        i = 1
        while i <= 3
          result = result + "x"
          i = i + 1
        end
        result
      AURA
      expect(code).to be_aua("xxx").and_be_a(Aua::Str)
    end
  end

  context "while loops with boolean conditions" do
    it "handles boolean variables in conditions" do
      code = <<~AURA
        running = true
        count = 0
        while running
          count = count + 1
          if count >= 3
            running = false
          end
        end
        count
      AURA
      expect(code).to be_aua(3).and_be_a(Aua::Int)
    end

    it "handles negated boolean conditions" do
      code = <<~AURA
        done = false
        count = 0
        while !done
          count = count + 1
          if count >= 2
            done = true
          end
        end
        count
      AURA
      expect(code).to be_aua(2).and_be_a(Aua::Int)
    end
  end

  context "infinite loop prevention" do
    # NOTE: These specs test that the implementation doesn't hang
    # In a real implementation, we might want loop iteration limits

    it "doesn't hang on theoretically infinite loops with eventual termination" do
      code = <<~AURA
        x = 0
        while x < 1000000
          x = x + 100000
        end
        x
      AURA
      expect(code).to be_aua(1_000_000).and_be_a(Aua::Int)
    end
  end

  context "while loop return values" do
    it "returns nihil from while loops" do
      code = <<~AURA
        i = 0
        result = while i < 2
          i = i + 1
        end
        result
      AURA
      expect(code).to be_aua(nil).and_be_a(Aua::Nihil)
    end
  end
end
