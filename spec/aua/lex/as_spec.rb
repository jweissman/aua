# frozen_string_literal: true

require "aua/lex"

RSpec.describe Aua::Lex do
  subject(:lexer) { described_class.new(input) }
  let(:tokens) { lexer.tokens.to_a }

  describe "as keyword lexing" do
    let(:input) { "x as T" }
    it "lexes 'as' as a :keyword token" do
      expect(tokens.map { |t| [t.type, t.value] }).to eq([
                                                           [:id, "x"],
                                                           [:as, "as"],
                                                           [:id, "T"]
                                                         ])
    end
  end
end
