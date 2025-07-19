require "spec_helper"

RSpec.describe "import builtin" do
  let(:test_script_content) do
    <<~AURA
      # Test script that can be imported
      say("Hello from imported script!")

      fun greet(name)
        "Hello, ${name}!"
      end

      # Return a meaningful value
      42
    AURA
  end

  let(:circular_import_a) do
    <<~AURA
      say("Script A importing B")
      import("/tmp/test_script_b.aura")
      "A complete"
    AURA
  end

  let(:circular_import_b) do
    <<~AURA
      say("Script B importing A")
      import("/tmp/test_script_a.aura")
      "B complete"
    AURA
  end

  before do
    # Create test files
    File.write("/tmp/test_script.aura", test_script_content)
    File.write("/tmp/test_script_a.aura", circular_import_a)
    File.write("/tmp/test_script_b.aura", circular_import_b)
  end

  after do
    # Clean up test files
    ["/tmp/test_script.aura", "/tmp/test_script_a.aura", "/tmp/test_script_b.aura"].each do |file|
      File.delete(file) if File.exist?(file)
    end

    # Clear import stack
    Thread.current[:aura_import_stack] = nil
  end

  context "when importing a valid script" do
    it "executes the script and returns its final value" do
      result = Aua.run('import("/tmp/test_script.aura")')

      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(42)
    end

    it "makes imported functions available in the current scope" do
      code = <<~AURA
        import("/tmp/test_script.aura")
        greet("World")
      AURA

      result = Aua.run(code)

      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hello, World!")
    end
  end

  context "when importing a non-existent file" do
    it "raises an error" do
      expect {
        Aua.run('import("/tmp/nonexistent.aura")')
      }.to raise_error(Aua::Error, /Cannot import.*file not found/)
    end
  end

  context "when circular imports are detected" do
    it "raises a circular import error" do
      expect {
        Aua.run('import("/tmp/test_script_a.aura")')
      }.to raise_error(Aua::Error, /Circular import detected/)
    end
  end

  context "with relative paths" do
    before do
      Dir.chdir("/tmp")
      File.write("relative_script.aura", 'say("Relative import works!"); 123')
    end

    after do
      File.delete("relative_script.aura") if File.exist?("relative_script.aura")
    end

    it "resolves relative paths correctly" do
      result = Aua.run('import("relative_script.aura")')

      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(123)
    end
  end

  context "when import argument is not a string" do
    it "raises a type error" do
      expect {
        Aua.run('import(42)')
      }.to raise_error(Aua::Error, /import requires a single Str argument/)
    end
  end
end
