# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Function Call Parsing" do
  def parse(code)
    tokens = Aua::Lex.new(code).enum_for(:tokenize)
    ctx = Aua::Runtime::Context.new(code)

    Aua::Parse.new(tokens, ctx).tree
  end

  describe "basic function calls" do
    it "parses function call with no arguments" do
      ast = parse("foo()")

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("foo")
      expect(ast.value[1]).to be_empty
    end

    it "parses function call with one argument" do
      ast = parse('greet("Alice")')

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("greet")
      expect(ast.value[1].length).to eq(1)
      expect(ast.value[1][0].type).to eq(:str)
      expect(ast.value[1][0].value).to eq("Alice")
    end

    it "parses function call with multiple arguments" do
      ast = parse("add(3, 4)")

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("add")
      expect(ast.value[1].length).to eq(2)
      expect(ast.value[1][0].type).to eq(:int)
      expect(ast.value[1][0].value).to eq(3)
      expect(ast.value[1][1].type).to eq(:int)
      expect(ast.value[1][1].value).to eq(4)
    end

    it "parses function call with mixed argument types" do
      ast = parse('create_person("Alice", 30, true)')

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("create_person")
      expect(ast.value[1].length).to eq(3)
      expect(ast.value[1][0].type).to eq(:str)
      expect(ast.value[1][1].type).to eq(:int)
      expect(ast.value[1][2].type).to eq(:bool)
    end
  end

  describe "nested function calls" do
    it "parses nested function calls as arguments" do
      ast = parse("outer(inner(42))")

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("outer")
      expect(ast.value[1].length).to eq(1)

      inner_call = ast.value[1][0]
      expect(inner_call.type).to eq(:call)
      expect(inner_call.value[0]).to eq("inner")
      expect(inner_call.value[1][0].type).to eq(:int)
    end

    it "parses function calls in arithmetic expressions" do
      ast = parse("add(3, 4) + multiply(2, 5)")

      expect(ast.type).to eq(:binop)
      expect(ast.value[0]).to eq(:plus)

      left_call = ast.value[1]
      expect(left_call.type).to eq(:call)
      expect(left_call.value[0]).to eq("add")

      right_call = ast.value[2]
      expect(right_call.type).to eq(:call)
      expect(right_call.value[0]).to eq("multiply")
    end
  end

  describe "function calls vs variable access" do
    it "distinguishes function calls from variable access" do
      # Variable access
      var_ast = parse("factorial")
      expect(var_ast.type).to eq(:id)
      expect(var_ast.value).to eq("factorial")

      # Function call
      call_ast = parse("factorial(5)")
      expect(call_ast.type).to eq(:call)
      expect(call_ast.value[0]).to eq("factorial")
    end
  end

  describe "whitespace handling" do
    it "handles whitespace around parentheses" do
      ast = parse("add ( 3 , 4 )")

      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("add")
      expect(ast.value[1].length).to eq(2)
    end

    it "handles multiline function calls" do
      code = <<~AURA
        calculate(
          first_arg,
          second_arg
        )
      AURA

      ast = parse(code)
      expect(ast.type).to eq(:call)
      expect(ast.value[0]).to eq("calculate")
      expect(ast.value[1].length).to eq(2)
    end
  end
end
