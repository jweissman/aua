# frozen_string_literal: true

require_relative "../obj"
require_relative "type_converter"

module Aua
  module Runtime
    # Registry for storing and retrieving custom type definitions
    class TypeRegistry
      def initialize
        @types = {}
      end

      # Register a new type definition
      # @param name [String] The name of the type
      # @param definition [AST::Node] The type definition AST node
      def register(name, definition)
        # Convert AST to runtime type using TypeConverter to prevent AST leaks
        @types[name] = TypeConverter.ast_to_runtime(definition, name, self)
      end

      # Look up a type by name
      # @param name [String] The name of the type to look up
      # @return [Aua::Klass, nil] The type object or nil if not found
      def lookup(name)
        @types[name]
      end

      # Check if a type is registered
      # @param name [String] The name of the type
      # @return [Boolean] true if the type exists
      def type?(name)
        @types.key?(name)
      end

      # Get all registered type names
      # @return [Array<String>] Array of type names
      def type_names
        @types.keys
      end

      # Helper method to wrap raw Ruby values in appropriate Aua objects
      def wrap_value(value)
        case value
        when Integer
          Aua::Int.new(value)
        when ::Float
          Aua::Float.new(value)
        when String
          Aua::Str.new(value)
        when TrueClass, FalseClass
          Aua::Bool.new(value)
        when Hash
          # For nested objects, wrap recursively
          wrapped_hash = {} # : Hash[String, Obj]
          value.each { |k, v| wrapped_hash[k] = wrap_value(v) }
          Aua::ObjectLiteral.new(wrapped_hash)
        when Array
          # For arrays, wrap each element and create an Aua::List
          wrapped_elements = value.map { |v| wrap_value(v) }
          Aua::List.new(wrapped_elements)
        else
          # For unknown types, pass through as-is
          value
        end
      end
    end
  end
end
