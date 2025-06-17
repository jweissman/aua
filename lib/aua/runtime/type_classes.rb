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
  end
end
