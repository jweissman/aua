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
        @types[name] = create_type_object(name, definition)
        # TypeConverter.ast_to_runtime(definition, name, self)
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

      # Legacy methods for backward compatibility - now redirected through TypeConverter
      private

      # Create a type object from an AST definition (legacy method)
      # @param name [String] The name of the type
      # @param definition [AST::Node] The type definition AST
      # @return [Aua::Klass] A type object
      def create_type_object(name, definition)
        # end
        type_obj = case definition.type
                   when :union_type
                     create_union_type(name, definition.value)
                   when :type_constant
                     create_constant_type(name, definition.value)
                   when :type_reference
                     create_reference_type(name, definition.value)
                   when :record_type
                     create_record_type(name, definition.value)
                   when :generic_type
                     create_generic_type(name, definition.value)
                   else
                     raise Error, "Unknown type definition: #{definition.type}"
                   end

        # Now use TypeConverter instead of inline AST handling
        actual_type = type_obj
        converted_type = TypeConverter.ast_to_runtime(definition, name, self)
        Aua.logger.info "Registered type: #{name} -> #{actual_type.inspect} [converted would be: #{converted_type.inspect}]"

        type_obj
      end

      # Create a union type (enum-like: 'yes' | 'no' or Type1 | Type2)
      def create_union_type(name, variants)
        Runtime::Union.new(name, variants, self)
      end

      # Create a constant type (single value like 'yes')
      def create_constant_type(name, value_node)
        Runtime::Constant.new(name, value_node)
      end

      # Create a reference type (refers to another type)
      def create_reference_type(name, referenced_name)
        Runtime::Reference.new(name, referenced_name)
      end

      # Create a record type (like { x: Int, y: Int })
      def create_record_type(name, fields)
        # Extract field definitions
        field_defs = extract_field_definitions(fields)

        # Create a proper RecordType class instead of metaprogramming
        Runtime::RecordType.new(name, field_defs, self)
      end

      # Create a generic type (like List<String>)
      def create_generic_type(name, type_info)
        # type_info should be [base_type, type_args]
        # For now, create a simple reference that includes the generic info
        Runtime::GenericType.new(name, type_info, self)
      end

      def extract_field_definitions(fields)
        fields.map do |field|
          field_name = field.value[0]
          field_type_def = field.value[1]

          # For now, just store the field name and type reference
          # In a full implementation, we'd resolve type references
          { name: field_name, type: field_type_def }
        end
      end

      public

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
