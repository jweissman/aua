module Aua
  module Runtime
    # A proper class to represent union types instead of metaprogramming
    class Union < Klass
      attr_reader :variants, :type_registry

      def initialize(name, variants, type_registry)
        super(name, Klass.obj)
        @variants = variants
        @type_registry = type_registry
      end

      def json_schema
        Runtime::JsonSchema.for_union_type(@variants, @type_registry)
      end

      def construct(value)
        # For union types, we typically return a string representation
        # In the future, this could be more sophisticated
        Aua::Str.new(value.to_s)
      end

      def union_values
        @union_values ||= extract_union_values(@variants)
      end

      private

      def extract_union_values(variants)
        variants.map do |variant|
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
      end
    end

    # A proper class to represent constant types instead of metaprogramming
    class Constant < Klass
      attr_reader :constant_value

      def initialize(name, value_node)
        super(name, Klass.obj)
        @constant_value = value_node.value
      end

      def json_schema
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

      def construct(value)
        Aua::Str.new(value.to_s)
      end
    end

    # A proper class to represent reference types instead of metaprogramming
    class Reference < Klass
      attr_reader :referenced_type

      def initialize(name, referenced_name)
        super(name, Klass.obj)
        @referenced_type = referenced_name
      end

      def json_schema
        # For now, assume it's a string-like type
        # In a full implementation, this would resolve the reference
        {
          type: "object",
          properties: {
            value: {
              type: "string"
            }
          }
        }
      end

      def construct(value)
        Aua::Str.new(value.to_s)
      end
    end

    # A proper class to represent generic types like List<String>
    class GenericType < Klass
      attr_reader :base_type, :type_args, :type_registry

      def initialize(name, type_info, type_registry)
        super(name, Klass.obj)
        @base_type = type_info[0]
        @type_args = type_info[1] || []
        @type_registry = type_registry
      end

      def json_schema
        Aua.logger.info "Generating JSON schema for generic type: #{@base_type} with args: #{@type_args.inspect}"
        case @base_type
        when "List"
          # For List<T>, generate array schema with appropriate item type
          item_type = if @type_args.any?
                        # Get the first type argument and convert to JSON schema type
                        first_arg = @type_args.first
                        type_arg_to_json_type(first_arg)
                      else
                        "object" # fallback
                      end

          {
            type: "object",
            properties: {
              value: {
                type: "array",
                items: { type: item_type }
              }
            },
            required: ["value"]
          }
        when "Dict"
          # For Dict<K, V>, generate object schema
          value_type = if @type_args.length >= 2
                         # Get the second type argument (value type) and convert to JSON schema type
                         second_arg = @type_args[1]
                         type_arg_to_json_type(second_arg)
                       else
                         "object" # fallback
                       end

          {
            type: "object",
            properties: {
              value: {
                type: "object",
                additionalProperties: { type: value_type }
              }
            },
            required: ["value"]
          }
        else
          # Fallback for unknown generic types
          {
            type: "object",
            properties: {
              value: { type: "object" }
            },
            required: ["value"]
          }
        end
      end

      def introspect
        # Create a readable string representation like "List<String>" or "List<Object>"
        if @type_args.any?
          type_arg_strings = @type_args.map { |arg| type_arg_to_string(arg) }
          "#{@base_type}<#{type_arg_strings.join(", ")}>"
        else
          @base_type
        end
      end

      private

      def type_arg_to_json_type(type_arg)
        # Convert a type argument to JSON schema type
        if type_arg.respond_to?(:name)
          case type_arg.name
          when "String", "Str" then "string"
          when "Int", "Integer" then "integer"
          when "Float", "Number" then "number"
          when "Bool", "Boolean" then "boolean"
          else "object"
          end
        elsif type_arg.respond_to?(:value)
          case type_arg.value
          when "String", "Str" then "string"
          when "Int", "Integer" then "integer"
          when "Float", "Number" then "number"
          when "Bool", "Boolean" then "boolean"
          else "object"
          end
        elsif type_arg.is_a?(Array)
          # Handle object/struct types like { name: String, age: Int }
          "object"
        else
          "object" # fallback
        end
      end

      def type_arg_to_string(type_arg)
        # Convert a type argument to a readable string representation

        # Handle IR types (new approach)
        if type_arg.is_a?(Aua::Runtime::IR::Types::TypeConstant) || type_arg.is_a?(Aua::Runtime::IR::Types::TypeReference)
          type_arg.name
        elsif type_arg.is_a?(Aua::Runtime::IR::Types::GenericType)
          param_strings = type_arg.type_params.map { |param| type_arg_to_string(param) }
          "#{type_arg.base_type}<#{param_strings.join(", ")}>"
        elsif type_arg.is_a?(Aua::Runtime::IR::Types::RecordType)
          # For record types like { name: String, age: Int }, return detailed structure
          field_strings = type_arg.fields.map do |field|
            "#{field[:name]} => #{type_arg_to_string(field[:type])}"
          end
          "{ #{field_strings.join(", ")} }"
        elsif type_arg.is_a?(Aua::Runtime::IR::Types::UnionType)
          variant_strings = type_arg.types.map { |variant| type_arg_to_string(variant) }
          variant_strings.join(" | ")

        # Handle legacy AST nodes
        elsif type_arg.respond_to?(:type) && type_arg.respond_to?(:value)
          # Handle AST nodes properly
          case type_arg.type
          when :record_type
            # For record types like { name: String, age: Int }, just return "Object"
            "Object"
          when :type_reference
            type_arg.value
          else
            type_arg.value.to_s
          end

        # Handle other objects with value or fallback
        elsif type_arg.respond_to?(:value)
          type_arg.value.to_s
        elsif type_arg.is_a?(Array)
          # Handle object/struct types like { name: String, age: Int }
          "Object"
        elsif type_arg.respond_to?(:name)
          # Catch-all for objects with name method
          type_arg.name
        else
          type_arg.to_s
        end
      end

      public

      def construct(value)
        # For generic types, we typically return a list representation
        # In the future, this could be more sophisticated
        case value
        when Array
          Aua::List.new(value.map { |v| @type_registry.wrap_value(v) })
        else
          Aua::List.new([])
        end
      end
    end
  end
end
