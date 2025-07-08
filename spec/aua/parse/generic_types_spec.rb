# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Parser Generic Types" do
  def parse(code)
    tokens = Aua::Lex.new(code).tokens
    parser = Aua::Parse.new(tokens)
    parser.tree
  end

  context "generic type syntax parsing in type contexts" do
    it "can parse type alias with List<String>" do
      ast = parse("type BookList = List<String>")

      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("BookList")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("List")
      expect(ast.value[1].value[1]).to be_an(Array)
      expect(ast.value[1].value[1][0].type).to eq(:type_reference)
      expect(ast.value[1].value[1][0].value).to eq("String")
    end

    it "can parse type alias with List<Int>" do
      ast = parse("type ScoreList = List<Int>")
      puts "AST for List<Int>: #{ast.inspect}"

      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("ScoreList")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("List")
      expect(ast.value[1].value[1]).to be_an(Array)
      # Let's check what Int becomes
      puts "Int type param: #{ast.value[1].value[1][0].inspect}"
    end

    it "can parse nested generic types in type context" do
      ast = parse("type NestedList = List<List<String>>")
      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("NestedList")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("List")
      # The nested List<String> should be in the type parameters array
      expect(ast.value[1].value[1]).to be_an(Array)
      expect(ast.value[1].value[1][0].type).to eq(:generic_type)
      expect(ast.value[1].value[1][0].value[0]).to eq("List")
      expect(ast.value[1].value[1][0].value[1]).to be_an(Array)
      expect(ast.value[1].value[1][0].value[1][0].type).to eq(:type_reference)
      expect(ast.value[1].value[1][0].value[1][0].value).to eq("String")
    end
  end

  context "type annotation syntax parsing" do
    it "can parse assignment with type annotation" do
      ast = parse("books = [] : BookList")
      expect(ast.type).to eq(:binop)
      expect(ast.value[0]).to eq(:equals)
      expect(ast.value[1].type).to eq(:id)
      expect(ast.value[1].value).to eq("books")
      expect(ast.value[2].type).to eq(:type_annotation)
      expect(ast.value[2].value[0].type).to eq(:array_literal)
      expect(ast.value[2].value[1].type).to eq(:type_reference)
      expect(ast.value[2].value[1].value).to eq("BookList")
    end

    it "can parse cast to generic type" do
      ast = parse("data as List<String>")
      expect(ast.type).to eq(:binop)
      expect(ast.value[0]).to eq(:as)
      expect(ast.value[1].type).to eq(:id)
      expect(ast.value[1].value).to eq("data")
      expect(ast.value[2].type).to eq(:generic_type)
      expect(ast.value[2].value[0]).to eq("List")
    end
  end

  context "type declarations with generics" do
    it "can parse type BookList = List<String>" do
      ast = parse("type BookList = List<String>")
      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("BookList")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("List")
    end

    it "can parse record type with generic field" do
      ast = parse("type Library = { name: String, books: List<String> }")
      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("Library")
      expect(ast.value[1].type).to eq(:record_type)

      # Check that the books field has a generic type
      books_field = ast.value[1].value.find { |field| field.value[0] == "books" }
      expect(books_field).not_to be_nil
      expect(books_field.value[1].type).to eq(:generic_type)
      expect(books_field.value[1].value[0]).to eq("List")
    end
  end

  context "complex generic types in type contexts" do
    it "can parse List with record type parameter" do
      ast = parse("type PersonList = List<{ name: String, age: Int }>")
      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("PersonList")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("List")
      expect(ast.value[1].value[1]).to be_a(Array)
      expect(ast.value[1].value[1].length).to eq(1)
      expect(ast.value[1].value[1][0].type).to eq(:record_type)
      expect(ast.value[1].value[1][0].value.length).to eq(2)
    end

    it "can parse Map with multiple type parameters" do
      ast = parse("type StringIntMap = Map<String, Int>")
      expect(ast.type).to eq(:type_declaration)
      expect(ast.value[0]).to eq("StringIntMap")
      expect(ast.value[1].type).to eq(:generic_type)
      expect(ast.value[1].value[0]).to eq("Map")
      expect(ast.value[1].value[1].length).to eq(2)
    end
  end
end
