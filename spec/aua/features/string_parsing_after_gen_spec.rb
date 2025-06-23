require "spec_helper"

RSpec.describe "String Type Parsing After Generative Strings" do
  describe "regular strings after generative strings" do
    it "parses regular interpolated strings correctly after triple-quoted strings" do
      # This tests the exact issue from bin/game where strings after """..."""
      # were being parsed as generative instead of regular
      script = <<~AUA
        name = "Alice"
        profession = """Generate a fantasy profession for ${name}"""
        say "Hello ${name}"
        say "You are a ${profession}"
      AUA

      # Parse and check the AST structure
      ast = Aua::Parse.new(Aua::Lex.new(script).tokens).tree
      statements = ast.value

      # statement 0: name = "Alice"
      expect(statements[0].type).to eq(:assign)

      # statement 1: profession = """...""" (should be structured_gen_lit)
      expect(statements[1].type).to eq(:assign)
      profession_assignment = statements[1].value[1]
      expect(profession_assignment.type).to eq(:structured_gen_lit)

      # statement 2: say "Hello ${name}" (should be structured_str, NOT structured_gen_lit)
      expect(statements[2].type).to eq(:call)
      hello_arg = statements[2].value[1][0] # first argument to say
      expect(hello_arg.type).to eq(:structured_str), "Expected structured_str but got #{hello_arg.type}"

      # statement 3: say "You are a ${profession}" (should be structured_str, NOT structured_gen_lit)
      expect(statements[3].type).to eq(:call)
      you_are_arg = statements[3].value[1][0] # first argument to say
      expect(you_are_arg.type).to eq(:structured_str), "Expected structured_str but got #{you_are_arg.type}"
    end

    it "does not send regular interpolated strings to LLM after generative strings" do
      # Mock the LLM to track calls
      mock_chat = instance_double(Aua::LLM::Chat)
      allow(Aua::LLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:ask).with("Generate a profession").and_return("Warrior")

      script = <<~AUA
        profession = """Generate a profession"""
        say "You are a ${profession}"
      AUA

      # Capture stdout to avoid cluttering test output
      captured_output = capture_stdout do
        Aua.run(script)
      end

      # Should only call LLM once for the generative string, not for the regular interpolated string
      expect(mock_chat).to have_received(:ask).once
      expect(captured_output).to include("You are a Warrior")
    end

    it "handles multiple regular strings after generative strings correctly" do
      mock_chat = instance_double(Aua::LLM::Chat)
      allow(Aua::LLM).to receive(:chat).and_return(mock_chat)
      allow(mock_chat).to receive(:ask).with("Generate a name").and_return("Bob")

      script = <<~AUA
        name = """Generate a name"""
        say "Hello ${name}"
        say "Welcome ${name}"
        say "Goodbye ${name}"
      AUA

      capture_stdout { Aua.run(script) }

      # Should only call LLM once for the generative string
      expect(mock_chat).to have_received(:ask).once
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
