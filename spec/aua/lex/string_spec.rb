# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua::Lex do
  describe "comprehensive string interpolation" do
    subject(:lexer) { described_class.new(input) }
    let(:tokens) { lexer.tokens.to_a }

    context "multiple consecutive interpolated strings" do
      let(:input) do
        <<~AURA
          name = ask "what is your name?"
          say "Hello ${name}"
          profession = """Provide a short profession for a fantasy character, ${name}. Give your answer as one word only with no spaces"""
          say "You are a ${profession}"
          greeting = "Welcome, ${name} the ${profession}!"
          say greeting
          stats = "Health: ${health}, Strength: ${strength}"
          inventory = "Gold: ${gold}, Items: ${items}"
          location = "You are in ${current_location}"
          description = """The ${weather} sky stretches above ${current_location}, where ${name} stands ready for adventure."""
          say description
        AURA
      end

      it "lexes all interpolated strings correctly" do
        token_map = tokens.map { |t| [t.type, t.value] }.to_a

        # Debug output to see what we actually get
        puts "\n=== All Tokens ==="
        token_map.each_with_index do |(type, value), index|
          puts "#{index}: [#{type}, #{value.inspect}]"
        end
        puts "=== End Tokens ===\n"

        # Split by EOS tokens to analyze line by line
        lines = token_map.chunk { |t| t.first == :eos }.reject { |k, _| k }.map(&:last)

        puts "\n=== Lines ==="
        lines.each_with_index do |line, index|
          puts "Line #{index}: #{line}"
        end
        puts "=== End Lines ===\n"

        # Line 1: name = ask "what is your name?"
        expect(lines[0]).to eq([
                                 [:id, "name"],
                                 [:equals, "="],
                                 [:id, "ask"],
                                 [:str_part, "what is your name?"],
                                 [:str_end, nil]
                               ])

        # Line 2: say "Hello ${name}"
        expect(lines[1]).to eq([
                                 [:id, "say"],
                                 [:str_part, "Hello "],
                                 [:interpolation_start, "${"],
                                 [:id, "name"],
                                 [:interpolation_end, "}"],
                                 [:str_end, nil]
                               ])

        # Line 3: profession = """Provide a short profession for a fantasy character, ${name}. Give your answer as one word only with no spaces"""
        profession_part = "Provide a short profession for a fantasy character, "
        expect(lines[2]).to eq([
                                 [:id, "profession"],
                                 [:equals, "="],
                                 [:str_part, profession_part],
                                 [:interpolation_start, "${"],
                                 [:id, "name"],
                                 [:interpolation_end, "}"],
                                 [:gen_lit, ". Give your answer as one word only with no spaces"]
                               ])

        # Line 4: say "You are a ${profession}"
        expect(lines[3]).to eq([
                                 [:id, "say"],
                                 [:str_part, "You are a "],
                                 [:interpolation_start, "${"],
                                 [:id, "profession"],
                                 [:interpolation_end, "}"],
                                 [:str_end, nil]
                               ])

        # Line 5: greeting = "Welcome, ${name} the ${profession}!"
        expect(lines[4]).to eq([
                                 [:id, "greeting"],
                                 [:equals, "="],
                                 [:str_part, "Welcome, "],
                                 [:interpolation_start, "${"],
                                 [:id, "name"],
                                 [:interpolation_end, "}"],
                                 [:str_part, " the "],
                                 [:interpolation_start, "${"],
                                 [:id, "profession"],
                                 [:interpolation_end, "}"],
                                 [:str_part, "!"],
                                 [:str_end, nil]
                               ])

        # Line 6: say greeting
        expect(lines[5]).to eq([
                                 [:id, "say"],
                                 [:id, "greeting"]
                               ])

        # Line 7: stats = "Health: ${health}, Strength: ${strength}"
        expect(lines[6]).to eq([
                                 [:id, "stats"],
                                 [:equals, "="],
                                 [:str_part, "Health: "],
                                 [:interpolation_start, "${"],
                                 [:id, "health"],
                                 [:interpolation_end, "}"],
                                 [:str_part, ", Strength: "],
                                 [:interpolation_start, "${"],
                                 [:id, "strength"],
                                 [:interpolation_end, "}"],
                                 [:str_end, nil]
                               ])

        # Line 8: inventory = "Gold: ${gold}, Items: ${items}"
        expect(lines[7]).to eq([
                                 [:id, "inventory"],
                                 [:equals, "="],
                                 [:str_part, "Gold: "],
                                 [:interpolation_start, "${"],
                                 [:id, "gold"],
                                 [:interpolation_end, "}"],
                                 [:str_part, ", Items: "],
                                 [:interpolation_start, "${"],
                                 [:id, "items"],
                                 [:interpolation_end, "}"],
                                 [:str_end, nil]
                               ])

        # Line 9: location = "You are in ${current_location}"
        expect(lines[8]).to eq([
                                 [:id, "location"],
                                 [:equals, "="],
                                 [:str_part, "You are in "],
                                 [:interpolation_start, "${"],
                                 [:id, "current_location"],
                                 [:interpolation_end, "}"],
                                 [:str_end, nil]
                               ])

        # Line 10: description = """The ${weather} sky stretches above ${current_location}, where ${name} stands \
        # ready for adventure."""
        expect(lines[9]).to eq([
                                 [:id, "description"],
                                 [:equals, "="],
                                 [:str_part, "The "],
                                 [:interpolation_start, "${"],
                                 [:id, "weather"],
                                 [:interpolation_end, "}"],
                                 [:str_part, " sky stretches above "],
                                 [:interpolation_start, "${"],
                                 [:id, "current_location"],
                                 [:interpolation_end, "}"],
                                 [:str_part, ", where "],
                                 [:interpolation_start, "${"],
                                 [:id, "name"],
                                 [:interpolation_end, "}"],
                                 [:gen_lit, " stands ready for adventure."]
                               ])

        # Line 11: say description
        expect(lines[10]).to eq([
                                  [:id, "say"],
                                  [:id, "description"]
                                ])
      end
    end

    context "edge cases for string machine state" do
      describe "alternating single and double quoted strings" do
        let(:input) do
          <<~AURA
            a = 'single'
            b = "double ${var1}"
            c = 'another single'
            d = "another double ${var2}"
            e = """generative ${var3}"""
            f = "final ${var4}"
          AURA
        end

        it "handles state transitions correctly" do
          token_map = tokens.map { |t| [t.type, t.value] }
          lines = token_map.chunk { |t| t.first == :eos }.reject { |k, _| k }.map(&:last)

          # Debug output
          puts "\n=== Alternating Quotes Test ==="
          lines.each_with_index do |line, index|
            puts "Line #{index}: #{line}"
          end
          puts "=== End Test ===\n"

          # Should not fail on any line
          expect(lines.size).to eq(6)

          # Each interpolated string should have proper structure
          expect(lines[1]).to include([:interpolation_start, "${"])
          expect(lines[3]).to include([:interpolation_start, "${"])
          expect(lines[4]).to include([:interpolation_start, "${"])
          expect(lines[5]).to include([:interpolation_start, "${"])
        end
      end

      describe "back-to-back interpolated strings" do
        let(:input) do
          <<~AURA
            say "First ${a}"
            say "Second ${b}"
            say "Third ${c}"
            say "Fourth ${d}"
            say "Fifth ${e}"
          AURA
        end

        it "handles consecutive interpolations without state corruption" do
          token_map = tokens.map { |t| [t.type, t.value] }
          lines = token_map.chunk { |t| t.first == :eos }.reject { |k, _| k }.map(&:last)

          # Debug output
          puts "\n=== Back-to-back Interpolations Test ==="
          lines.each_with_index do |line, index|
            puts "Line #{index}: #{line}"
          end
          puts "=== End Test ===\n"

          # All lines should have interpolation structure
          lines.each_with_index do |line, index|
            expect(line).to include([:interpolation_start, "${"]), "Line #{index} missing interpolation start"
            expect(line).to include([:interpolation_end, "}"]), "Line #{index} missing interpolation end"
            expect(line).to include([:str_end, nil]), "Line #{index} missing string end"
          end
        end
      end

      describe "nested quotes and complex interpolations" do
        let(:input) do
          <<~AURA
            complex = "User ${name} said: 'Hello ${greeting}' to ${target}"
            nested = """The character ${name} exclaimed: "I have ${gold} gold!"."""
            mixed = "Status: ${status}, Location: '${location}', Health: ${health}%"
          AURA
        end

        it "handles complex quote nesting and interpolation" do
          # This test is designed to catch edge cases in quote handling
          # and ensure the string machine properly manages quote context
          expect { tokens }.not_to raise_error

          token_map = tokens.map { |t| [t.type, t.value] }

          # Debug output
          puts "\n=== Complex Nesting Test ==="
          puts "Tokens: #{token_map}"
          puts "=== End Test ===\n"

          # Should produce some tokens without crashing
          expect(tokens.size).to be > 0
        end
      end
    end

    context "string machine debugging" do
      describe "single interpolation regression" do
        let(:input) { 'greeting = "Welcome, ${name} the ${profession}!"' }

        it "handles multiple interpolations in one string" do
          token_map = tokens.map { |t| [t.type, t.value] }

          puts "\n=== Single String Multiple Interpolations ==="
          puts "Input: #{input}"
          puts "\nTokens:"
          token_map.each_with_index do |(type, value), index|
            puts "  #{index}: [#{type}, #{value.inspect}]"
          end
          puts "=== End Debug ===\n"

          # Should handle both interpolations correctly
          expect(token_map).to include([:interpolation_start, "${"])
          expect(token_map).to include([:id, "name"])
          expect(token_map).to include([:interpolation_end, "}"])
          expect(token_map).to include([:str_part, " the "])
          expect(token_map).to include([:id, "profession"])
        end
      end
      describe "minimal failing case" do
        let(:input) do
          <<~AURA
            first = "Hello ${name}"
            second = "Goodbye ${name}"
          AURA
        end

        it "provides detailed token analysis for debugging" do
          token_map = tokens.map { |t| [t.type, t.value] }

          puts "\n=== Minimal Failing Case Debug ==="
          puts "Input:"
          puts input
          puts "\nTokens:"
          token_map.each_with_index do |(type, value), index|
            puts "  #{index}: [#{type}, #{value.inspect}]"
          end

          # Check for unexpected tokens or missing interpolation markers
          interpolation_starts = token_map.count { |t| t.first == :interpolation_start }
          interpolation_ends = token_map.count { |t| t.first == :interpolation_end }

          puts "\nInterpolation markers:"
          puts "  Starts: #{interpolation_starts}"
          puts "  Ends: #{interpolation_ends}"
          puts "=== End Debug ===\n"

          # Both interpolations should be properly tokenized
          expect(interpolation_starts).to eq(2)
          expect(interpolation_ends).to eq(2)
        end
      end
    end
  end
end
