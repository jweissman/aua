# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Type System End-to-End", skip: false do
  describe "type declaration and lookup" do
    it "can declare and lookup types without LLM casting" do
      code = <<~AUA
        type YesNo = 'yes' | 'no'
        YesNo
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("YesNo")
      expect(result.union_values).to eq(%w[yes no])
    end

    it "can use types in environment after declaration" do
      # First, let's make sure the type gets registered
      vm = Aua::Runtime::VM.new
      type_ast = Aua::AST::Node.new(
        type: :union_type,
        value: [
          Aua::AST::Node.new(type: :type_constant, value: Aua::AST::Node.new(type: :simple_str, value: "yes", at: nil),
                             at: nil),
          Aua::AST::Node.new(type: :type_constant, value: Aua::AST::Node.new(type: :simple_str, value: "no", at: nil),
                             at: nil)
        ],
        at: nil
      )

      result = vm.send :eval_type_declaration, "YesNo", type_ast
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("YesNo")

      # Now check that it's in the environment
      looked_up = vm.send :eval_type_lookup, "YesNo"
      expect(looked_up).to eq(result)
    end
  end
end
