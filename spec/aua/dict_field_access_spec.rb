require 'spec_helper'

RSpec.describe "Dict field access" do
  describe "accessing fields on Dict objects" do
    it "allows field access with dot notation" do
      code = <<~AURA
        data = load_yaml("spec/fixtures/dict_test.yml")
        data.field1
      AURA

      expect(code).to be_aua("value1").and_be_a(Aua::Str)
    end

    it "raises error for non-existent fields" do
      code = <<~AURA
        data = load_yaml("spec/fixtures/dict_test.yml")
        data.nonexistent_field
      AURA

      expect { Aua.run(code) }.to raise_error(Aua::Error, /Key 'nonexistent_field' not found in dictionary/)
    end

    it "supports nested field access" do
      code = <<~AURA
        data = load_yaml("spec/fixtures/dict_test.yml")
        data.nested
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Dict)
      expect(result.get_field("inner").value).to eq("nested_value")
    end

    it "works with array fields" do
      code = <<~AURA
        data = load_yaml("spec/fixtures/dict_test.yml")
        data.items
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::List)
      expect(result.values.length).to eq(2)
    end
  end
end
