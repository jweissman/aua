# frozen_string_literal: true

require "debug"
require "spec_helper"
require "aua/lex"
require "pbt"

module Aua
  module Properties
    include Pbt::Arbitrary
    include Pbt::Arbitrary::ArbitraryMethods

    def ident
      tuple(ident_start, array(ident_rest, min: 0, max: 11))
        .map(
          ->(v) { v.respond_to?(:join) ? v.join : v },
          lambda(&:to_s) # Convert to string for consistency
        )
    end

    def int
      IntegerArbitrary.new(0, 1_000_000_000).map(
        lambda(&:to_s),
        lambda(&:to_i) # Convert to integer and back to string for consistency
      )
    end

    def float
      tuple(int, int).map(
        ->(v) { "#{v[0]}.#{v[1]}" },
        ->(s) { s.to_f.to_s } # Convert to float and back to string for consistency
      )
    end

    def str_lit
      ascii_string
        .filter { |s| s.length <= 8 && !s.include?("'") && !s.include?("\"") }
        .map(
          lambda { |v|
            if rand < 0.5
              "'#{v}'"
            else
              "\"#{v}\""
            end
          },
          ->(s) { s[1..-2] }
        )
    end

    def binop(lhs = ident, rhs = ident)
      ops = ["+", "-", "*", "/", "="]
      tuple(
        lhs,
        one_of(*ops),
        rhs
      ).map(
        ->(v) { "#{v[0]} #{v[1]} #{v[2]}" },
        ->(s) { s.split(/\s+/, 3) }
      )
    end

    protected

    def ident_start = one_of(*lowercase, *uppercase, "_")
    def ident_rest = one_of(*lowercase, *uppercase, "_")

    def id_joined(fst, *rst) = [fst, *rst].join

    private

    def lowercase = ("a".."z").to_a
    def uppercase = ("A".."Z").to_a
  end

  RSpec.describe "Lexer fuzzing" do
    # DSL for property-based tests that yields a string identifier
    let(:num_runs) { ENV["CI"] ? 10_000 : 100 }

    def with_property(arb, &block)
      Pbt.assert(num_runs:) do
        Pbt.property(arb) do |value|
          puts value
          block.call(value)
        end
      end
    end

    it "lexes valid identifiers as :identifier" do
      extend Aua::Properties
      with_property(ident) do |input|
        lexer = Lex.new(input)
        tokens = lexer.tokens.to_a.reject { |t| t.type == :whitespace }
        expect(tokens.size).to eq(1)
        expect(tokens.first.type).to eq(:id)
      end
    end

    it "lexes valid integer literals as :int" do
      extend Aua::Properties
      with_property(int) do |input|
        lexer = Lex.new(input) # .to_s)
        tokens = lexer.tokens.to_a.reject { |t| t.type == :whitespace }
        expect(tokens.size).to eq(1)
        expect(tokens.first.type).to eq(:int)
      end
    end

    it "lexes valid float literals as :float" do
      extend Aua::Properties
      with_property(float) do |input|
        lexer = Lex.new(input)
        tokens = lexer.tokens.to_a.reject { |t| t.type == :whitespace }
        expect(tokens.size).to eq(1)
        expect(tokens.first.type).to eq(:float)
      end
    end

    it "lexes valid string literals as :str kinds" do
      extend Aua::Properties
      with_property(str_lit) do |input|
        lexer = Lex.new(input)
        tokens = lexer.tokens.to_a.reject { |t| t.type == :whitespace }
        expect(1..2).to include(tokens.size) # .to eq(1..2)
        expect(%i[simple_str str str_part str_end]).to include(tokens.first.type)
      end
    end

    it "lexes random shallow binary expressions to valid token sequences" do
      extend Aua::Properties
      valid_types = Set[:id, :int, :float, :plus, :minus, :star, :slash, :equals, :lparen, :rparen, :identifier,
                        :simple_str, :str, :whitespace]
      with_property(binop) do |input|
        lexer = Lex.new(input)
        tokens = lexer.tokens.to_a
        tokens.each do |tok|
          expect(valid_types).to include(tok.type)
        end
      end
    end
  end
end
