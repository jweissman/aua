# frozen_string_literal: true

require "spec_helper"
require "aua/lex"

module Aua
  RSpec.describe Lex do
    let(:lexer) { described_class.new(input) }
    let(:tokens) { lexer.tokens.to_a }

    describe "unexpected characters" do
      let(:input) { "x = 42 @ unexpected" }
      it "raises an error for unexpected characters" do
        expect { tokens }.to raise_error(Aua::Error, /Invalid token: unexpected character at/)
      end
    end

    describe "comments" do
      describe "ignores single-line comments" do
        let(:input) { "x = 42 # This is a comment" }
        it "ignores comments after octothorpe (#)" do
          expect(tokens.map { [it.type, it.value] }).to eq([
            [:id, "x"], [:equals, "="], [:int, 42],
          ])
        end
      end
    end

    describe "literal" do
      describe "gen-string literal" do
        let(:input) { "\"\"\"The current day is #{Time.now.strftime("%A")}. Please come up with a rhyming couplet that describes the day of the week. If you can try to be alliterative, starting as many words as you can with the first two characters of the day name.\"\"\"" }
        it "captures the full string, including the first two characters" do

          # Find the string token (adjust type as needed)
          str_token = tokens.find { |t| t.type == :gen_lit }
          expect(str_token).not_to be_nil
          expect(str_token.value).to start_with("The current day is ")
          expect(str_token.value).to match Time.now.strftime("%A")
          expect(str_token.value).to end_with("day name.")
          expect(str_token.value.length).to be >= 2
        end
      end

      describe "single-quoted string literal" do
        it "lexes a single-quoted string without hanging", skip: false do
          input = "'hello'"
          lexer = described_class.new(input)
          tokens = lexer.tokens.to_a
          str_token = tokens.find { |t| t.type == :simple_str }
          expect(str_token).not_to be_nil
          expect(str_token.value).to eq("hello")
        end
      end
    end
  end
end
