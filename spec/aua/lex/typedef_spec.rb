# frozen_string_literal: true

require "aua/lex"

RSpec.describe Aua::Lex do
  subject(:lex) { described_class.new(input) }
  let(:tokens) { lex.tokens.to_a }

  context "type with union syntax" do
    let(:input) { "type YesNo = 'yes' | 'no'" }

    it "lexes type keyword, id, equals, simple_str, pipe, simple_str" do
      expect(tokens.map(&:type)).to eq(%i[
                                         keyword id equals simple_str pipe simple_str
                                       ])
      expect(tokens[0].value).to eq("type")
      expect(tokens[1].value).to eq("YesNo")
      expect(tokens[3].value).to eq("yes")
      expect(tokens[5].value).to eq("no")
    end
  end
end
