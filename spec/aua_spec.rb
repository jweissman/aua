# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.tap { $stdout = original_stdout }
  end

  describe "High-level Integration" do
    context "with multiple commands and output" do
      let(:input) do
        <<~AURA
          x = 5
          y = x + 2
          say "The result is: ${y}"
        AURA
      end

      it "evaluates multiple commands and returns the last result" do
        stdout = with_captured_stdout { Aua.run(input) }
        expect(stdout).to include("The result is: 7")
      end
    end

    context "with realistic shebang" do
      let(:input) { "#!/usr/bin/env aura\nx = 42\nx + 1" }
      it "runs the script with shebang and returns the result" do
        result = Aua.run(input)
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(43)
      end
    end

    context "with complex nested expressions" do
      let(:input) { "x = (1 + 2) * 3; y = x - 4; z = y * 2; x + y + z" }
      it "evaluates nested expressions correctly" do
        result = Aua.run(input)
        expect(result).to be_a(Aua::Int)
        expect(result.value).to eq(24)
      end
    end
  end
end
