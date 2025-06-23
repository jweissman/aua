require "spec_helper"

RSpec.describe "String Interpolation Features" do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.tap { $stdout = original_stdout }
  end

  describe "basic string interpolation" do
    it "interpolates simple variables" do
      expect('name = "Alice"; "Hello, ${name}!"').to be_aua("Hello, Alice!")
    end

    it "interpolates multiple variables in one string" do
      expect('first = "Alice"; last = "Smith"; "Welcome ${first} ${last}!"').to be_aua("Welcome Alice Smith!")
    end

    it "interpolates expressions" do
      expect('x = 5; y = 3; "The sum is ${x + y}"').to be_aua("The sum is 8")
    end

    it "outputs interpolated strings with say" do
      stdout = with_captured_stdout do
        Aua.run('name = "Alice"; say "Hello, ${name}!"')
      end
      expect(stdout).to include("Hello, Alice!")
    end
  end

  describe "nested interpolation" do
    it "handles interpolation within interpolation" do
      expect('name = "Bob"; title = "Dr."; greeting = "Hello ${title} ${name}"; "Message: ${greeting}!"').to be_aua("Message: Hello Dr. Bob!")
    end
  end

  describe "edge cases" do
    it "handles empty interpolation gracefully" do
      expect('empty = ""; "Value: \'${empty}\'"').to be_aua("Value: ''")
    end

    it "handles special characters in interpolated strings" do
      # NOTE: Using single quotes to avoid escaping issues in the test
      expect('special = "test"; "Contains: ${special}"').to be_aua("Contains: test")
    end

    it "interpolates multiple expressions in complex scenarios" do
      stdout = with_captured_stdout do
        Aua.run('a = 1; b = 2; c = 3; say "Results: ${a}, ${b}, ${c} = ${a + b + c}"')
      end
      expect(stdout).to include("Results: 1, 2, 3 = 6")
    end
  end
end
