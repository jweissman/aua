# frozen_string_literal: true

require "spec_helper"
require "aua/lex"

module Aua
  RSpec.describe Lex do
    subject(:lexer) { described_class.new(input) }
    let(:tokens) { lexer.tokens.to_a }
    let(:token) { tokens.first }

    context "basic" do
      describe "semicolon" do
        context "at the end of a statement" do
          let(:input) { "x = 42;" }
          describe "emits eos" do
            it "returns an end-of-statement token" do
              expect(tokens.last.type).to eq(:eos)
              expect(tokens.last.value).to be_nil
            end
          end
        end
      end

      describe "newline" do
        context "at the end of a statement" do
          let(:input) { "x = 42\n " }
          it "returns an end-of-statement token" do
            puts "Tokens: #{tokens.map { |t| [t.type, t.value] }}"
            expect(tokens.last.type).to eq(:eos)
            expect(tokens.last.value).to be_nil
          end
        end

        context "in the middle of a statement" do
          let(:input) { "x = 42\n y = 43" }
          it "returns an end-of-statement token for the first line" do
            expect(tokens.map { |t| [t.type, t.value] }).to eq([
                                                                 [:id, "x"], [:equals, "="], [:int, 42],
                                                                 [:eos, nil],
                                                                 [:id, "y"], [:equals, "="], [:int, 43]
                                                               ])
          end
        end
      end

      describe "comments" do
        describe "mixed use" do
          let(:input) { "x = 42 # This is a comment" }
          it "ignores after octothorpe (#)" do
            expect(tokens.map { [it.type, it.value] }).to eq([
                                                               [:id, "x"], [:equals, "="], [:int, 42]
                                                             ])
          end
        end

        describe "on their own line" do
          let(:input) { "# just a comment\n" }
          it "ignores" do
            expect(tokens).to be_empty
          end
        end

        describe "with leading whitespace" do
          let(:input) { "   #!/usr/bin/env aura\n" }
          it "ignores" do
            expect(tokens).to be_empty
          end
        end
      end

      describe "whitespace" do
        describe "spaces" do
          let(:input) { "  " }
          it "returns no tokens" do
            expect(tokens).to be_empty
          end
        end

        describe "only newline" do
          let(:input) { "   \n\t  " }
          it "returns no tokens" do
            expect(tokens).not_to be_empty
            expect(tokens.map { |t| [t.type, t.value] }).to eq([[:eos, nil]])
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
                                                                 [:id, "x"], [:equals, "="], [:int, 42]
                                                               ])
          end
        end
      end

      describe "identifiers" do
        context "with digits after the first character" do
          let(:input) { "foo42" }
          it "lexes as a single identifier" do
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

      describe "double-quoted" do
        let(:input) { '"hello"' }
        it "lexes a double-quoted string without hanging", skip: false do
          expect(tokens.size).to eq(2)
          expect(tokens.map { |t| [t.type, t.value] }).to eq([
                                                               [:str_part, "hello"],
                                                               [:str_end, ""]
                                                             ])
        end
      end

      describe "double-quoted with interpolation" do
        let(:input) { '"hello ${123}"' }
        it "interpolates a double-quoted string without hanging", skip: false do
          expect(tokens.size).to eq(5)
          expect(tokens.map { |t| [t.type, t.value] }).to eq([
                                                               [:str_part, "hello "],
                                                               [:interpolation_start, "${"],
                                                               [:int, 123],
                                                               [:interpolation_end, "}"],
                                                               [:str_end, ""]
                                                             ])
        end
      end

      describe "double-quoted with multiple interpolations" do
        let(:input) { '"The results are ${x} and ${y}"' }
        it "interpolates multiple variables in a double-quoted string" do
          expect(tokens.size).to eq(9)
          token_map = tokens.map { |t| [t.type, t.value] }
          expect(token_map).to eq([
                                    [:str_part, "The results are "],
                                    [:interpolation_start, "${"],
                                    [:id, "x"],
                                    [:interpolation_end, "}"],
                                    [:str_part, " and "],
                                    [:interpolation_start, "${"],
                                    [:id, "y"],
                                    [:interpolation_end, "}"],
                                    [:str_end, ""]
                                  ])
        end
      end

      describe "generative" do
        let(:input) do
          # NOTE: this is a manual ruby interpolation not a 'real' generative string interpolation!
          "\"\"\"The current day is #{::Time.now.strftime("%A")}.\"\"\""
        end

        it "lexes" do
          str_token = tokens.find { |t| t.type == :gen_lit }
          expect(str_token).not_to be_nil
          expect(str_token.value).to start_with("The current day is ")
          expect(str_token.value).to match ::Time.now.strftime("%A")
          expect(str_token.value).to end_with("day.")
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
          str_token = tokens.find { |t| t.type == :str_end }
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

    describe "multi-line fragments" do
      let(:input) do
        <<~AURA
          x = 5
          y = x + 2
          say "The result is: ${y}"
        AURA
      end

      it "lexes multi-line input correctly" do
        list = tokens.map { |t| [t.type, t.value] }
        fst = list.take(4)
        expect(fst).to eq([
                            [:id, "x"], [:equals, "="], [:int, 5],
                            [:eos, nil]
                          ])

        list = list.drop(4)
        snd = list.take(6)
        expect(snd).to eq([
                            [:id, "y"], [:equals, "="], [:id, "x"],
                            [:plus, nil], # Interesting that this is a nil value
                            [:int, 2],
                            [:eos, nil]
                          ])

        list = list.drop(6)
        expect(list).to eq([
                             [:id, "say"], [:str_part, "The result is: "],
                             [:interpolation_start, "${"],
                             [:id, "y"],
                             [:interpolation_end, "}"],
                             [:str_end, ""],
                             [:eos, nil]
                           ])
      end
    end
  end
end
