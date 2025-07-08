module Aua
  module Runtime
    # Module responsible for generating JSON schemas for types
    # This supports LLM casting and type validation
    module JsonSchema
      # Generate JSON schema for a record type
      # @param field_definitions [Array<Hash>] Field definitions with :name and :type
      # @param type_registry [TypeRegistry] Registry to look up nested types
      # @return [Hash] JSON schema object
      def self.for_record_type(field_definitions, type_registry)
        properties = {} # : Hash[String, Hash[untyped, untyped]]
        required = [] # : Array[String]

        field_definitions.each do |field_def|
          field_name = field_def[:name]
          field_type = field_def[:type]
          required << field_name

          # debugger

          properties[field_name] = schema_for_type(field_type, type_registry)
          Aua.logger.info "Field: #{field_name} - Schema: #{properties[field_name].inspect}"
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

      # Generate JSON schema for a union type
      # @param variants [Array] Union type variants
      # @param type_registry [TypeRegistry] Registry to look up nested types
      # @return [Hash] JSON schema object
      def self.for_union_type(variants, _type_registry)
        # Extract string values like the original implementation
        choices = variants.map do |variant|
          case variant.type
          when :type_constant
            variant.value.value
          when :type_reference
            variant.value
          else
            raise Error, "Unsupported union variant: #{variant.type}"
          end
        end

        choices = choices.select { |v| v.is_a?(String) }

        {
          type: "object",
          properties: {
            value: {
              type: "string",
              enum: choices
            }
          }
        }
      end

      class << self
        private

        # Generate schema for a single type
        # @param type_def [AST::Node] Type definition
        # @param type_registry [TypeRegistry] Registry to look up nested types
        # @return [Hash] JSON schema fragment
        def schema_for_type(type_def, type_registry)
          case type_def.type
          when :type_reference
            schema_for_type_reference(type_def.value, type_registry)
          when :generic_type
            # Handle generic types like List<String>, Dict<String, Int>
            base_type = type_def.value[0]
            type_args = type_def.value[1] || []

            case base_type
            when "List"
              # Generate array schema with items type
              item_type_schema = if type_args.any?
                                   schema_for_type(type_args.first, type_registry)
                                 else
                                   { type: "object" }
                                 end
              { type: "array", items: item_type_schema }
            when "Dict"
              # Generate object schema with additionalProperties type
              value_type_schema = if type_args.length >= 2
                                    schema_for_type(type_args[1], type_registry)
                                  else
                                    { type: "object" }
                                  end
              { type: "object", additionalProperties: value_type_schema }
            else
              # For unknown generic types, default to object
              { type: "object" }
            end
          when :type_constant
            # For literal types like 'active' | 'inactive'
            { enum: [type_def.value.value] }
          else
            # For complex types, default to string
            { type: "string" }
          end
        end

        # Generate schema for a type reference
        # @param type_name [String] Name of the referenced type
        # @param type_registry [TypeRegistry] Registry to look up the type
        # @return [Hash] JSON schema fragment
        def schema_for_type_reference(type_name, type_registry)
          case type_name
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
            if type_registry.type?(type_name)
              nested_type = type_registry.lookup(type_name)
              if nested_type.respond_to?(:json_schema)
                # Get the nested type's schema and extract the inner structure
                nested_schema = nested_type.json_schema
                extract_inner_schema(nested_schema)
              else
                # For non-record types (like enums), use string
                { type: "string", description: "#{type_name} value" }
              end
            else
              # For unknown types, default to string
              { type: "string" }
            end
          end
        end

        # Extract inner schema from wrapped schemas
        # @param schema [Hash] Full schema object
        # @return [Hash] Inner schema or original schema
        def extract_inner_schema(schema)
          if schema.is_a?(Hash) && schema[:type] == "object" &&
             schema[:properties] && schema[:properties][:value]
            # This is a wrapped schema, extract the inner object
            schema[:properties][:value]
          else
            # Use the schema as-is
            schema
          end
        end
      end
    end
  end
end
