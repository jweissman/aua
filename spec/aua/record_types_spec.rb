# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Record Types E2E" do
  it "can parse record type definitions" do
    code = "type Point = { x: Int, y: Int }"

    # Test basic parsing
    lex = Aua::Lex.new(code)
    tokens = lex.tokens
    parse = Aua::Parse.new(tokens)
    ast = parse.tree

    expect(ast.type).to eq(:type_declaration)
    expect(ast.value[0]).to eq("Point")
    expect(ast.value[1].type).to eq(:record_type)

    fields = ast.value[1].value
    expect(fields.length).to eq(2)
    expect(fields[0].type).to eq(:field)
    expect(fields[0].value[0]).to eq("x")
    expect(fields[0].value[1].type).to eq(:type_reference)
    expect(fields[0].value[1].value).to eq("Int")
  end

  it "can parse object literals" do
    code = "{ x: 3, y: 4 }"

    lex = Aua::Lex.new(code)
    tokens = lex.tokens
    parse = Aua::Parse.new(tokens)
    ast = parse.tree

    expect(ast.type).to eq(:object_literal)
    expect(ast.value.length).to eq(2)

    fields = ast.value
    expect(fields[0].type).to eq(:field)
    expect(fields[0].value[0]).to eq("x")
    expect(fields[0].value[1].type).to eq(:int)
    expect(fields[0].value[1].value).to eq(3)
  end

  it "can parse member access" do
    code = "result.x"

    lex = Aua::Lex.new(code)
    tokens = lex.tokens
    parse = Aua::Parse.new(tokens)
    ast = parse.tree

    expect(ast.type).to eq(:binop)
    expect(ast.value[0]).to eq(:dot)
    expect(ast.value[1].type).to eq(:id)
    expect(ast.value[1].value).to eq("result")
    expect(ast.value[2].type).to eq(:id)
    expect(ast.value[2].value).to eq("x")
  end
end
