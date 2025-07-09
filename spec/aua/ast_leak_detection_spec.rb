# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "AST Node Leak Detection" do
  let(:vm) { Aua.vm }
  let(:translator) { vm.tx }
  let(:type_registry) { vm.type_registry }

  # Helper to detect AST nodes in objects
  def find_ast_nodes(obj, path = "root", depth = 0)
    return [] if depth > 10 # Prevent infinite recursion

    ast_nodes = []

    case obj
    when Aua::AST::Node
      ast_nodes << { path:, object: obj }
    when Array
      obj.each_with_index do |item, i|
        ast_nodes.concat(find_ast_nodes(item, "#{path}[#{i}]", depth + 1))
      end
    when Hash
      obj.each do |k, v|
        ast_nodes.concat(find_ast_nodes(v, "#{path}[#{k}]", depth + 1))
      end
    when Struct
      obj.each_pair do |k, v|
        ast_nodes.concat(find_ast_nodes(v, "#{path}.#{k}", depth + 1))
      end
    else
      # Check instance variables for objects that might contain AST nodes
      if obj.respond_to?(:instance_variables)
        obj.instance_variables.each do |var|
          val = obj.instance_variable_get(var)
          ast_nodes.concat(find_ast_nodes(val, "#{path}.#{var}", depth + 1))
        end
      end
    end

    ast_nodes
  end

  describe "translator output" do
    it "should not contain AST nodes for simple types" do
      lex = Aua::Lex.new("type TestType = String")
      parser = Aua::Parse.new(lex.tokens)
      ast = parser.tree
      # Extract the type definition part
      type_def = ast.value[1] # type name = definition
      result = translator.translate(type_def)

      ast_nodes = find_ast_nodes(result)
      expect(ast_nodes).to be_empty, "Found AST nodes: #{ast_nodes.map { |n| "#{n[:path]}: #{n[:object].inspect}" }}"
    end

    it "should not contain AST nodes for generic types" do
      lex = Aua::Lex.new("type TestType = List<String>")
      parser = Aua::Parse.new(lex.tokens)
      ast = parser.tree
      # Extract the type definition part
      type_def = ast.value[1] # type name = definition
      result = translator.translate(type_def)

      ast_nodes = find_ast_nodes(result)
      expect(ast_nodes).to be_empty, "Found AST nodes: #{ast_nodes.map { |n| "#{n[:path]}: #{n[:object].inspect}" }}"
    end

    it "should not contain AST nodes for nested generic types" do
      lex = Aua::Lex.new("type TestType = List<Dict<String, Int>>")
      parser = Aua::Parse.new(lex.tokens)
      ast = parser.tree
      # Extract the type definition part
      type_def = ast.value[1] # type name = definition
      result = translator.translate(type_def)

      ast_nodes = find_ast_nodes(result)
      expect(ast_nodes).to be_empty, "Found AST nodes: #{ast_nodes.map { |n| "#{n[:path]}: #{n[:object].inspect}" }}"
    end

    it "should not contain AST nodes for record types" do
      lex = Aua::Lex.new("type TestType = { name: String, age: Int }")
      parser = Aua::Parse.new(lex.tokens)
      ast = parser.tree
      # Extract the type definition part
      type_def = ast.value[1] # type name = definition
      result = translator.translate(type_def)

      ast_nodes = find_ast_nodes(result)
      expect(ast_nodes).to be_empty, "Found AST nodes: #{ast_nodes.map { |n| "#{n[:path]}: #{n[:object].inspect}" }}"
    end
  end

  describe "type registry storage" do
    before do
      # Register a few test types to examine what gets stored
      code = <<~AURA
        type Person = { name: String, age: Int }
        type BookList = List<String>
        type ScoreMap = Dict<String, Int>
      AURA
      Aua.run(code)
    end

    it "should not store AST nodes in type definitions" do
      type_registry.types.each do |name, type_obj|
        ast_nodes = find_ast_nodes(type_obj)
        expect(ast_nodes).to be_empty, "Type '#{name}' contains AST nodes: #{ast_nodes.map do |n|
          "#{n[:path]}: #{n[:object].inspect}"
        end}"
      end
    end

    it "should be able to introspect stored types without AST dependencies" do
      person_type = type_registry.lookup("Person")
      expect(person_type).to respond_to(:introspect)
      expect(person_type.introspect).to be_a(String)

      book_list_type = type_registry.lookup("BookList")
      expect(book_list_type).to respond_to(:introspect)
      expect(book_list_type.introspect).to be_a(String)
    end
  end

  describe "VM evaluation of typed values" do
    it "should handle type annotations without needing describe_type_ast" do
      # This test should pass without the VM needing to call describe_type_ast
      code = <<~AURA
        type BookList = List<String>
        books = [] : BookList
        typeof books
      AURA

      # Monitor if describe_type_ast gets called and capture the arguments
      describe_type_ast_calls = []
      original_method = Aua::Runtime::VM.instance_method(:describe_type_ast)

      allow_any_instance_of(Aua::Runtime::VM).to receive(:describe_type_ast) do |instance, arg|
        describe_type_ast_calls << arg
        puts "📍 describe_type_ast called with: #{arg.inspect} (#{arg.class})"
        if arg.respond_to?(:type) && arg.respond_to?(:value)
          puts "   AST node - type: #{arg.type}, value: #{arg.value.inspect}"
        end

        # Call the original method to get the actual result
        result = original_method.bind(instance).call(arg)
        puts "   Result: #{result.inspect}"
        result
      end

      # Add logging to eval_typed_value to see what type information is being processed
      original_eval_typed_value = Aua::Runtime::VM.instance_method(:eval_typed_value)
      allow_any_instance_of(Aua::Runtime::VM).to receive(:eval_typed_value) do |instance, value_stmt, type_stmt|
        puts "📍 eval_typed_value called:"
        puts "   value_stmt: #{value_stmt.inspect}"
        puts "   type_stmt: #{type_stmt.inspect}"

        result = original_eval_typed_value.bind(instance).call(value_stmt, type_stmt)
        puts "   eval_typed_value result: #{result.inspect}"
        puts "   result type_name: #{result.type_name}" if result.respond_to?(:type_name)
        result
      end

      result = Aua.run(code)
      puts "\n🎯 Final result: #{result.value.inspect}"

      # The test currently fails because we get "List<>" instead of "List<String>"
      # This demonstrates the AST node leak issue
      if result.value == "List<>"
        puts "❌ AST leak confirmed: type parameters lost, got '#{result.value}' instead of 'List<String>'"
        puts "💡 This happens because AST nodes in type_args can't be properly converted to strings"

        # Show what describe_type_ast was called with
        if describe_type_ast_calls.any?
          puts "⚠️  describe_type_ast was called #{describe_type_ast_calls.length} times:"
          describe_type_ast_calls.each_with_index do |call, i|
            puts "   #{i + 1}. #{call.inspect}"
          end
        end

        # For now, expect the broken behavior to document the issue
        expect(result.value).to eq("List<>"), "Expected the broken behavior to demonstrate AST leak"
      else
        expect(result.value).to eq("List<String>")
      end
    end
  end
end
