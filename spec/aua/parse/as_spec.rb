# frozen_string_literal: true

require "aua/parse"
require "aua/lex"

RSpec.describe Aua::Parse do
  subject(:parse) { described_class.new(tokens) }
  let(:lex) { Aua::Lex.new(input) }
  let(:tokens) { lex.tokens }
  let(:ast) { parse.tree }

  describe "typecast expression parsing" do
    let(:input) { "x as T" }
    it "parses 'x as T' as an :as node" do
      expect(ast.type).to eq(:binop)
      expect(ast.value[0]).to eq(:as)
      expect(ast.value[1].type).to eq(:id)
      expect(ast.value[1].value).to eq("x")
      expect(ast.value[2].type).to eq(:type_reference)
      expect(ast.value[2].value).to eq("T")
    end
  end
end
