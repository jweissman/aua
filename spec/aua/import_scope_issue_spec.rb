require "spec_helper"

RSpec.describe "import scope sharing" do
  before do
    # Create a simple script that defines a function
    File.write("/tmp/simple_script.aura", 'fun add(a, b); a + b; end; 123')
  end

  after do
    File.delete("/tmp/simple_script.aura") if File.exist?("/tmp/simple_script.aura")
  end

  it "shows import now works correctly - functions are shared between scopes" do
    # This should work: import a script, then use functions it defined
    code = <<~AURA
      result = import("/tmp/simple_script.aura")
      say("Import returned: \#{result}")
      sum = add(10, 20)
      sum
    AURA

    # This should now work because add() is available in the same VM's environment
    result = Aua.run(code)
    expect(result).to be_a(Aua::Int)
    expect(result.value).to eq(30)
  end
end
