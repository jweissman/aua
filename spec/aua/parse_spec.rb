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

    describe "structured strings" do
      let(:input) { '"The result is: ${y}"' }
      it "parses interpolated strings into an AST" do
        extend Aua::Grammar
        expect(ast.type).to eq(:structured_str)
        expect(ast.value).to eq([s(:str, "The result is: "), s(:id, "y")])
      end
    end

    describe "strings with multiple interpolations" do
      let(:input) { '"The results are ${x} and ${y}"' }
      it "parses a string with multiple interpolations as a :structured_str node" do
        extend Aua::Grammar
        # puts(tokens.to_a.map { |t| [t.type, t.value] }.inspect)
        expect(ast.type).to eq(:structured_str)
        expect(ast.value).to eq([
                                  s(:str, "The results are "),
                                  s(:id, "x"),
                                  s(:str, " and "),
                                  s(:id, "y")
                                ])
      end
    end

    describe "structured generative strings" do
      let(:input) { "\"\"\"The current time is: ${time 'now'}\"\"\"" }
      it "parses structured generative strings with function calls" do
        extend Aua::Grammar
        expect(ast.type).to eq(:structured_gen_lit)
        expect(ast.value).to eq([
                                  s(:str, "The current time is: "),
                                  s(:call, ["time", [s(:simple_str, "now")]])
                                ])
      end
    end
  end

  describe "command and function call parsing" do
    context "parensless command form" do
      let(:input) { "say 'hello'" }
      it "parses as a :call node with one argument" do
        expect(ast.type).to eq(:call)
        expect(ast.value[0]).to eq("say")
        expect(ast.value[1].size).to eq(1)
        expect(ast.value[1][0].type).to eq(:simple_str)
        expect(ast.value[1][0].value).to eq("hello")
      end
    end

    context "parenthesized function call form" do
      let(:input) { "say('hello')" }
      it "parses as a :funcall node with one argument" do
        expect(ast.type).to eq(:call)
        expect(ast.value[0]).to eq("say")
        expect(ast.value[1].size).to eq(1)
        expect(ast.value[1][0].type).to eq(:simple_str)
        expect(ast.value[1][0].value).to eq("hello")
      end
    end
  end

  describe "command and string interactions" do
    let(:input) do
      <<~AURA
        x = 5
        y = x + 2
        say "The result is: ${y}"
      AURA
    end

    it "parses commands with string interpolation" do
      expect(ast.type).to eq(:seq)
      expect(ast.value.size).to eq(3)

      lines = ast.value
      expect(lines[0].type).to eq(:assign)
      expect(lines[1].type).to eq(:assign)
      expect(lines[2].type).to eq(:call)
      expect(lines[2].value[0]).to eq("say")

      extend Aua::Grammar
      expect(lines[2].value[1]).to eq([
                                        s(:structured_str, [
                                            s(:str, "The result is: "),
                                            s(:id, "y")
                                          ])
                                      ])
    end
  end

  describe "commands after gen lits" do
    let(:input) do
      <<~AURA
        profession = """Please invent a short profession for a character. One word only. No spaces"""
        say "You are a ${profession}"
      AURA
    end

    it "parses commands following generative literals" do
      expect(ast.type).to eq(:seq)
      expect(ast.value.size).to eq(2)

      lines = ast.value
      expect(lines[0].type).to eq(:assign)
      expect(lines[1].type).to eq(:call)
      expect(lines[1].value[0]).to eq("say")

      extend Aua::Grammar
      expect(lines[1].value[1]).to eq([
                                        s(:structured_str, [
                                            s(:str, "You are a "),
                                            s(:id, "profession")
                                          ])
                                      ])
    end
  end
  describe "commands after gen lits containing interpolative gen lits" do
    let(:input) do
      <<~AURA
        profession = """Please invent a short profession for a character. One word only. No spaces"""

        say """Please describe a character with the profession ${profession}"""
      AURA
    end

    it "parses commands following generative literals" do
      # puts tokens.to_a.map { |t| [t.type, t.value] }.inspect
      expect(ast.type).to eq(:seq)
      expect(ast.value.size).to eq(2)

      lines = ast.value
      expect(lines[0].type).to eq(:assign)
      expect(lines[1].type).to eq(:call)
      expect(lines[1].value[0]).to eq("say")

      extend Aua::Grammar
      expect(lines[1].value[1]).to eq([
                                        s(:structured_gen_lit, [
                                            s(:str, "Please describe a character with the profession "),
                                            s(:id, "profession")
                                          ])
                                      ])
    end
  end

  describe "complex command parsing" do
    let(:input) do
      <<~AURA
        say "hello world"
        say "this is a simple game that shows how to use the aura framework"
        name = ask "what is your name?"
        say "Hello ${name}"
        profession = """Please invent a short profession for a character"""
        say "You are a ${profession}"
      AURA
    end

    it "parses a sequence of commands with string interpolation" do
      # puts tokens.to_a.map { |t| [t.type, t.value] }.inspect

      expect(ast.type).to eq(:seq)
      expect(ast.value.size).to eq(6)

      lines = ast.value

      extend Aua::Grammar
      expect(lines[0].type).to eq(:call)
      expect(lines[0].value[0]).to eq("say")
      expect(lines[0].value[1]).to eq([s(:str, "hello world")])

      expect(lines[1].type).to eq(:call)
      expect(lines[1].value[0]).to eq("say")
      expect(lines[1].value[1]).to eq([s(:str,
                                         "this is a simple game that shows how to use the aura framework")])

      expect(lines[2].type).to eq(:assign)
      expect(lines[2].value[0]).to eq("name")
      expect(lines[2].value[1]).to eq(s(:call, ["ask", [s(:str, "what is your name?")]]))

      expect(lines[3].type).to eq(:call)
      expect(lines[3].value[0]).to eq("say")
      expect(lines[3].value[1]).to eq([s(:structured_str, [s(:str, "Hello "), s(:id, "name")])])

      expect(lines[4].type).to eq(:assign)
      expect(lines[4].value[0]).to eq("profession")
      expect(lines[4].value[1]).to eq(s(:structured_gen_lit,
                                        [s(:str,
                                           "Please invent a short profession for a character")]))
    end
  end
end
