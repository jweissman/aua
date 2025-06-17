# frozen_string_literal: true

require_relative "../obj"

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
        when :record_type
          create_record_type(name, definition.value)
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

      # Create a record type (like { x: Int, y: Int })
      def create_record_type(name, fields)
        # Extract field definitions
        field_defs = fields.map do |field|
          field_name = field.value[0]
          field_type_def = field.value[1]

          # For now, just store the field name and type reference
          # In a full implementation, we'd resolve type references
          { name: field_name, type: field_type_def }
        end

        # Create a custom Klass for the record type
        klass = Klass.new(name, Klass.obj)
        klass.instance_variable_set(:@field_definitions, field_defs)

        # Add methods to make it behave like a proper Klass
        klass.define_singleton_method(:field_definitions) { @field_definitions }
        klass.define_singleton_method(:name) { name }
        klass.define_singleton_method(:introspect) { name }

        # Add JSON schema support for LLM casting
        registry = self # Capture registry reference for closure
        klass.define_singleton_method(:json_schema) do
          properties = {} # : Hash[String, Hash]
          required = [] # : Array[String]

          @field_definitions.each do |field_def|
            field_name = field_def[:name]
            field_type = field_def[:type]
            required << field_name

            # Map type references to JSON schema types
            properties[field_name] = case field_type.type
                                     when :type_reference
                                       case field_type.value
                                       when "Int"
                                         { type: "integer" }
                                       when "Float"
                                         { type: "number" }
                                       when "Str"
                                         { type: "string" }
                                       when "Bool"
                                         { type: "boolean" }
                                       when "List"
                                         { type: "array", items: { type: "string" } }
                                       else
                                         # Check if this is a user-defined type
                                         if registry.has_type?(field_type.value)
                                           nested_type = registry.lookup(field_type.value)
                                           if nested_type.respond_to?(:json_schema)
                                             # Get the nested type's schema and extract the inner structure
                                             nested_schema = nested_type.json_schema
                                             if nested_schema.is_a?(Hash) && nested_schema[:type] == "object" && nested_schema[:properties] && nested_schema[:properties][:value]
                                               # This is a wrapped schema, extract the inner object
                                               nested_schema[:properties][:value]
                                             else
                                               # Use the schema as-is
                                               nested_schema
                                             end
                                           else
                                             # For non-record types (like enums), use string
                                             { type: "string", description: "#{field_type.value} value" }
                                           end
                                         else
                                           # For unknown types, default to string
                                           { type: "string" }
                                         end
                                       end
                                     else
                                       # For complex types, default to string for now
                                       { type: "string" }
                                     end
          end

          {
            type: "object",
            properties: {
              value: {
                type: "object",
                properties: properties,
                required: required
              }
            }
          }
        end
        type_registry = self
        klass.define_singleton_method(:construct) do |value|
          # Value should be a hash with the field values
          # Wrap raw values in appropriate Aua objects, with recursive casting for record types
          wrapped_values = {} # : Hash[String, Obj]
          value.each do |field_name, field_value|
            # Find the field definition for this field
            field_def = @field_definitions.find { |fd| fd[:name] == field_name }
            if field_def && field_def[:type].type == :type_reference
              field_type_name = field_def[:type].value

              # Check if this field should be a record type
              if type_registry.has_type?(field_type_name)
                field_type = type_registry.lookup(field_type_name)

                # If it's a record type and we have a hash, recursively cast it
                wrapped_values[field_name] = if field_type.respond_to?(:field_definitions) && field_value.is_a?(Hash)
                                               field_type.construct(field_value)
                                             else
                                               # For non-record types or non-hash values, use regular wrapping
                                               type_registry.wrap_value(field_value)
                                             end
              else
                # For built-in types, use regular wrapping
                wrapped_values[field_name] = type_registry.wrap_value(field_value)
              end
            else
              # For fields without type info, use regular wrapping
              wrapped_values[field_name] = type_registry.wrap_value(field_value)
            end
          end

          # Create a structured object that supports member access
          result = Aua::RecordObject.new(name, @field_definitions, wrapped_values)
          result
        end

        klass
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
