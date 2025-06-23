# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Empty String Parsing" do
  context "basic empty string" do
    it "parses empty string literal" do
      expect('""').to be_aua("").and_be_a(Aua::Str)
    end
  end

  context "empty string in expression" do
    it "parses empty string equality" do
      expect('"" == ""').to be_aua(true).and_be_a(Aua::Bool)
    end
  end
end
