# frozen_string_literal: true

require "aua/parse"
require "aua/lex"

RSpec.describe Aua::Parse do
  subject(:parse) { described_class.new(tokens) }
  let(:lex) { Aua::Lex.new(input) }
  let(:tokens) { lex.tokens }
  let(:ast) { parse.tree }

  describe "string interpolation parsing" do
    describe "plain strings" do
      let(:input) { '"hello"' }
      it "parses a plain string as a :str node" do
        expect(ast.type).to eq(:str)
        expect(ast.value).to eq("hello")
      end
    end

    # describe "strings with interpolation" do
    #   let(:input) { '"The result is: ${y}"' }
    #   it "parses a string with interpolation as a :str node (for now)" do
    #     expect(ast.type).to eq(:str)
    #     expect(ast.value).to eq("The result is: ${y}")
    #   end
    # end

    describe "structured strings" do
      let(:input) { '"The result is: ${y}"' }
      it "parses interpolated strings into an AST" do
        extend Aua::Grammar
        expect(ast.type).to eq(:structured_str)
        expect(ast.value).to eq([s(:str, "The result is: "), s(:id, "y")])
      end
    end
  end
end
