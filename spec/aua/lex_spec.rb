# frozen_string_literal: true

require "spec_helper"
require "aua/lex"

module Aua
  RSpec.describe Lex do
    subject(:lexer) { described_class.new(input) }
    let(:tokens) { lexer.tokens.to_a }
    let(:token) { tokens.first }

    describe "comments" do
      describe "mixed use" do
        let(:input) { "x = 42 # This is a comment" }
        it "ignores after octothorpe (#)" do
          expect(tokens.map { [it.type, it.value] }).to eq([
            [:id, "x"], [:equals, "="], [:int, 42],
          ])
        end
      end

      describe "on their own line" do
        let(:input) { "# just a comment\n" }
        it "ignores" do
          expect(tokens).to be_empty
        end
      end
    end

    describe "whitespace" do
      describe "only" do
        let(:input) { "   \n\t  " }
        it "returns no tokens" do
          expect(tokens).to be_empty
        end
      end

      describe "leading and trailing" do
        let(:input) { "   42   " }
        it "ignores" do
          expect(tokens.map { |t| [t.type, t.value] }).to eq([[:int, 42]])
        end
      end

      describe "between tokens" do
        let(:input) { "x   =   42" }
        it "ignores" do
          expect(tokens.map { |t| [t.type, t.value] }).to eq([
            [:id, "x"], [:equals, "="], [:int, 42],
          ])
        end
      end
    end

    describe "identifiers" do
      context "with digits after the first character" do
        let(:input) { "foo42" }
        it "lexes as a single identifier (currently fails, see lexer impl)", skip: true do
          expect(tokens.size).to eq(1)
          expect(token.type).to eq(:id)
          expect(token.value).to eq("foo42")
        end
      end

      context "starting with underscore" do
        let(:input) { "_foo" }
        it "lexes as a single identifier" do
          expect(tokens.size).to eq(1)
          expect(token.type).to eq(:id)
          expect(token.value).to eq("_foo")
        end
      end
    end

    describe "numbers" do
      context "with leading zeroes" do
        let(:input) { "007" }

        it "lexes :int" do
          expect(tokens.size).to eq(1)
          expect(token.type).to eq(:int)
          expect(token.value).to eq(7)
        end
      end

      context "with trailing decimal point" do
        let(:input) { "42." }
        it "lexes :float" do
          expect(tokens.size).to eq(1)
          expect(tokens.first.type).to eq(:float)
        end
      end

      context "negative numbers" do
        let(:input) { "-42" }
        it "lexes as :minus, :int" do
          expect(tokens.size).to eq(2)
          expect(tokens[0].type).to eq(:minus)
          expect(tokens[1].type).to eq(:int)
          expect(tokens[1].value).to eq(42)
        end
      end
    end

    describe "strings" do
      describe "single-quoted" do
        let(:input) { "'hello'" }
        it "lexes a single-quoted string without hanging", skip: false do
          str_token = tokens.find { |t| t.type == :simple_str }
          expect(str_token).not_to be_nil
          expect(str_token.value).to eq("hello")
        end
      end

      describe "generative" do
        let(:input) { "\"\"\"The current day is #{::Time.now.strftime("%A")}. Please come up with a rhyming couplet that describes the day of the week. If you can try to be alliterative, starting as many words as you can with the first two characters of the day name.\"\"\"" }

        it "lexes" do
          str_token = tokens.find { |t| t.type == :gen_lit }
          expect(str_token).not_to be_nil
          expect(str_token.value).to start_with("The current day is ")
          expect(str_token.value).to match ::Time.now.strftime("%A")
          expect(str_token.value).to end_with("day name.")
          expect(str_token.value.length).to be >= 2
        end

        context "with newlines" do
          let(:input) { "\"\"\"hello\nworld\"\"\"" }
          it "lexes triple-quoted multi-line string literal" do
            str_token = tokens.find { |t| t.type == :gen_lit }
            expect(str_token).not_to be_nil
            expect(str_token.value).to include("hello\nworld")
          end
        end
      end

      describe "empty str" do
        let(:input) { '""' }
        it "lexes an empty string literal" do
          str_token = tokens.find { |t| t.type == :str }
          expect(str_token).not_to be_nil
          expect(str_token.value).to eq("")
        end
      end

      describe "empty single-quoted str" do
        it "lexes an empty single-quoted string literal" do
          input = "''"
          lexer = described_class.new(input)
          tokens = lexer.tokens.to_a
          str_token = tokens.find { |t| t.type == :simple_str }
          expect(str_token).not_to be_nil
          expect(str_token.value).to eq("")
        end
      end
    end

    describe "errors", slow: true do
      describe "foundations" do
        describe "empty input" do
          let(:input) { "" }
          it "returns an empty token stream" do
            expect(tokens).to be_empty
          end
        end

        describe "standalone dot" do
          let(:input) { "." }
          it "raises an error for unexpected character" do
            expect { tokens }.to raise_error(Aua::Error)
          end
        end
        describe "unexpected characters" do
          let(:input) { "x = 42 @ unexpected" }
          it "raises an error for unexpected characters" do
            expect { tokens }.to raise_error(Aua::Error, /Invalid token: unexpected character at/)
          end
        end
      end

      context "with numbers" do
        describe "identifier immediately following" do
          let(:input) { "42abc" }
          it "raises an error" do
            expect { tokens }.to raise_error(Aua::Error, /number immediately followed by identifier/)
          end
        end

        describe "multiple dots" do
          let(:input) { "1.2.3" }
          it "raises an error for invalid float" do
            expect { tokens }.to raise_error(Aua::Error, /multiple dots in number/)
          end
        end

        describe "only decimal point" do
          let(:input) { ".42" }
          it "raises an error for invalid float" do
            expect { tokens }.to raise_error(Aua::Error, /Invalid token: unexpected character at line 1, column 1/)
          end
        end
      end

      context "with strings" do
        describe "unterminated literal" do
          let(:input) { "'unterminated" }
          it "raises an error" do
            expect { lexer.tokens.to_a }.to raise_error(Aua::Error, /Unterminated string literal/)
          end
        end

        describe "very long string" do
          let(:input) { '"' + "a" * 70_000 + '"' }
          it "raises an error for exceeding MAX_STRING_LENGTH", skip: false do
            expect { tokens }.to raise_error(Aua::Error, /Unterminated string literal/)
          end
        end
      end
    end
  end
end
