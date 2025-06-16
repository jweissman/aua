# frozen_string_literal: true

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
        @types[name] = create_type_object(name, definition)
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
      def has_type?(name)
        @types.key?(name)
      end

      # Get all registered type names
      # @return [Array<String>] Array of type names
      def type_names
        @types.keys
      end

      private

      # Create a type object from an AST definition
      # @param name [String] The name of the type
      # @param definition [AST::Node] The type definition AST
      # @return [Aua::Klass] A type object
      def create_type_object(name, definition)
        case definition.type
        when :union_type
          create_union_type(name, definition.value)
        when :type_constant
          create_constant_type(name, definition.value)
        when :type_reference
          create_reference_type(name, definition.value)
        else
          raise Error, "Unknown type definition: #{definition.type}"
        end
      end

      # Create a union type (enum-like: 'yes' | 'no' or Type1 | Type2)
      def create_union_type(name, variants)
        # Extract the possible values from the union
        values = variants.map do |variant|
          case variant.type
          when :type_constant
            # This is a string literal like 'yes'
            variant.value.value
          when :type_reference
            # This is a reference to another type
            variant.value
          else
            raise Error, "Unsupported union variant: #{variant.type}"
          end
        end

        # Create a custom Klass that knows about its union values
        klass = Klass.new(name, Klass.obj)
        klass.instance_variable_set(:@union_values, values)

        # Add methods to make it behave like a proper Klass
        klass.define_singleton_method(:union_values) { @union_values }
        klass.define_singleton_method(:name) { name }
        klass.define_singleton_method(:introspect) { name }

        # Add JSON schema support for LLM casting
        klass.define_singleton_method(:json_schema) do
          {
            type: "object",
            properties: {
              value: {
                type: "string",
                enum: @union_values.select { |v| v.is_a?(String) }
              }
            }
          }
        end

        # Add construct method to create instances
        klass.define_singleton_method(:construct) do |value|
          # For union types, we typically return a string representation
          # In the future, this could be more sophisticated
          Aua::Str.new(value.to_s)
        end

        klass
      end

      # Create a constant type (single value like 'yes')
      def create_constant_type(name, value_node)
        value = value_node.value
        klass = Klass.new(name, Klass.obj)
        klass.instance_variable_set(:@constant_value, value)

        # Add standard methods
        klass.define_singleton_method(:constant_value) { @constant_value }
        klass.define_singleton_method(:name) { name }
        klass.define_singleton_method(:introspect) { name }

        # JSON schema for single value
        klass.define_singleton_method(:json_schema) do
          {
            type: "object",
            properties: {
              value: {
                type: "string",
                const: @constant_value
              }
            }
          }
        end

        # Construct method
        klass.define_singleton_method(:construct) do |value|
          Aua::Str.new(value.to_s)
        end

        klass
      end

      # Create a reference type (refers to another type)
      def create_reference_type(name, referenced_name)
        # For now, just create a simple reference
        # In a full implementation, this would need to resolve the reference
        klass = Klass.new(name, Klass.obj)
        klass.instance_variable_set(:@referenced_type, referenced_name)

        # Add standard methods
        klass.define_singleton_method(:referenced_type) { @referenced_type }
        klass.define_singleton_method(:name) { name }
        klass.define_singleton_method(:introspect) { name }

        # For now, assume it's a string-like type
        klass.define_singleton_method(:json_schema) do
          {
            type: "object",
            properties: {
              value: {
                type: "string"
              }
            }
          }
        end

        klass.define_singleton_method(:construct) do |value|
          Aua::Str.new(value.to_s)
        end

        klass
      end
    end
  end
end
