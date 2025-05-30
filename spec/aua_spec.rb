# frozen_string_literal: true

RSpec.describe Aua do
  it "has a version number" do
    expect(Aua::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(Aua.run("123")).to eq(123)
  end
end
