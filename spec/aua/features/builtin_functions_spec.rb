require "spec_helper"

RSpec.describe "Builtin Functions (E2E)", :llm do
  describe "cast function" do
    it "supports function call syntax with two arguments" do
      # Test basic cast function call with parentheses
      result = Aua.run('cast("hello", Str)')
      expect(result.value).to eq("hello")
    end

    it "casts string to integer" do
      result = Aua.run('cast("42", Int)')
      expect(result.value).to eq(42)
    end

    it "casts integer to string" do
      result = Aua.run("cast(42, Str)")
      expect(result.value).to eq("42")
    end

    it "handles nested function calls as arguments" do
      # This tests both multiple arguments and nested calls
      result = Aua.run('cast(inspect("test"), Str)')
      expect(result.value).to eq('"test"')
    end
  end

  describe "other multi-argument builtins" do
    # Add more multi-arg builtin tests here as we discover/create them
  end
end
