require "spec_helper"

RSpec.describe "Generative String Features", gen: true do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.tap { $stdout = original_stdout }
  end

  describe "simple generative strings" do
    it "evaluates gen literals and returns strings" do
      result = Aua.run('"""Generate a greeting"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to be_a(String)
      expect(result.value.length).to be > 0
    end

    it "evaluates gen literals when assigned to variables" do
      result = Aua.run('greeting = """Generate a greeting"""; greeting')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to be_a(String)
    end

    it "works with say builtin" do
      stdout = with_captured_stdout do
        Aua.run('say """Generate a greeting"""')
      end
      expect(stdout.length).to be > 0
    end
  end

  describe "interpolated generative strings" do
    it "interpolates variables before sending to LLM" do
      result = Aua.run('name = "Alice"; """Say hello to ${name}"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Alice")
    end

    it "handles complex interpolation in generative strings" do
      result = Aua.run('name = "Bob"; age = 25; """Create a story about ${name} who is ${age} years old"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Bob")
      expect(result.value).to include("25")
    end
  end

  describe "nested generative strings" do
    # NOTE: Direct nested gen literals in interpolation aren't currently supported
    # This is a known limitation that could be addressed in parser improvements

    it "handles gen literals via variables in interpolation" do
      result = Aua.run('compliment = """Generate a compliment"""; "AI says: ${compliment}"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to start_with("AI says:")
      expect(result.value.length).to be > 10
    end

    it "outputs gen literals via variables correctly with say" do
      stdout = with_captured_stdout do
        Aua.run('response = """Generate a short response"""; say "AI response: ${response}"')
      end
      expect(stdout).to start_with("AI response:")
      expect(stdout.length).to be > 15
    end
  end

  describe "chat function equivalence" do
    it "treats gen literals as equivalent to chat() calls" do
      result1 = Aua.run('"""Tell me a joke"""')
      result2 = Aua.run('chat("Tell me a joke")')

      expect(result1).to be_a(Aua::Str)
      expect(result2).to be_a(Aua::Str)
      # Both should be strings, content may vary
      expect(result1.value).to be_a(String)
      expect(result2.value).to be_a(String)
    end

    it "interpolated gen literals work like interpolated chat calls" do
      result1 = Aua.run('name = "Charlie"; """Say hello to ${name}"""')
      result2 = Aua.run('name = "Charlie"; chat("Say hello to ${name}")')

      expect(result1).to be_a(Aua::Str)
      expect(result2).to be_a(Aua::Str)
      expect(result1.value).to include("Charlie")
      expect(result2.value).to include("Charlie")
    end
  end

  describe "integration with other features" do
    it "works with conditional statements" do
      result = Aua.run('name = "Dave"; if true then """Say hello to ${name}""" else "goodbye"')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Dave")
    end

    it "works in function calls with multiple arguments" do
      stdout = with_captured_stdout do
        Aua.run('say """Generate a greeting"""; say "That was generated!"')
      end
      expect(stdout).to include("That was generated!")
      # Should contain some generated content before the static message
      lines = stdout.split("\n")
      expect(lines.length).to be >= 2
    end
  end
end
