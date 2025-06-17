# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Built-in Functions Features" do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.tap { $stdout = original_stdout }
  end

  describe "I/O functions" do
    it "prints to standard output with single-quoted str" do
      stdout = with_captured_stdout { Aua.run("say 'hi'") }
      expect(stdout).to include("hi")
    end

    it "prints to standard output with double-quoted str" do
      stdout = with_captured_stdout { Aua.run('say "hello world"') }
      expect(stdout).to include("hello world")
    end

    it "prints to standard output with generative string" do
      stdout = with_captured_stdout { Aua.run('say """hello world"""') }
      expect(stdout).to include("How can I")
    end

    it "evaluates multiple commands with output" do
      input = <<~AURA
        x = 5
        y = x + 2
        say "The result is: ${y}"
      AURA

      stdout = with_captured_stdout { Aua.run(input) }
      expect(stdout).to include("The result is: 7")
    end
  end

  describe "time and date functions" do
    it "returns the current time" do
      result = Aua.run("time 'now'")
      expect(result).to be_a(Aua::Time)
      expect(result.value).to be_within(1).of(Time.now)
    end
  end

  describe "random number generation" do
    it "generates a random integer within a range" do
      result = Aua.run("rand(10)")
      expect(result).to be_a(Aua::Int)
      expect(result.value).to be_between(0, 10).inclusive
    end
  end
end
