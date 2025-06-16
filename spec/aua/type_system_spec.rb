# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Type System Integration" do
  describe "parsing and type registry" do
    it "can parse type declarations and register them" do
      code = "type YesNo = 'yes' | 'no'"

      # Test parsing
      lex = Aua::Lex.new(code)
      tokens = lex.tokens
      parse = Aua::Parse.new(tokens)
      ast = parse.tree

      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("YesNo")
      expect(ast.value[1].type).to eq(:union_type)

      # Test type registry (once VM is fixed)
      # vm = Aua::Runtime::VM.new
      # result = vm.evaluate_one(ast)
      # expect(result).to be_a(Aua::Klass)
      # expect(result.name).to eq("YesNo")
    end

    it "can parse more complex type definitions" do
      code = "type Status = 'active' | 'inactive' | 'pending'"

      lex = Aua::Lex.new(code)
      tokens = lex.tokens
      parse = Aua::Parse.new(tokens)
      ast = parse.tree

      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("Status")
      expect(ast.value[1].type).to eq(:union_type)
      expect(ast.value[1].value.length).to eq(3)
    end
  end
end
