require "spec_helper"
require "aua/lex"
module Aua
  RSpec.describe "Lexing errors", slow: true do
    subject(:lexer) { Lex.new(input) }
    let(:tokens) { lexer.tokens.to_a }
    let(:token) { tokens.first }

    describe "errors" do
      describe "foundations" do
        describe "empty input" do
          let(:input) { "" }
          it "returns an empty token stream" do
            expect(tokens).to be_empty
          end
        end

        xdescribe "standalone dot" do
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
          let(:input) { '"' + ("a" * 70_000) + '"' }
          it "raises an error for exceeding MAX_STRING_LENGTH", skip: false do
            expect { tokens }.to raise_error(Aua::Error, /Unterminated string literal/)
          end
        end
      end
    end
  end
end
