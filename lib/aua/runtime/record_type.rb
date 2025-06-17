module Aua
  module Runtime
    # A proper class to represent record types instead of metaprogramming
    class RecordType < Klass
      attr_reader :field_definitions, :type_registry

      def initialize(name, field_definitions, type_registry)
        super(name, Klass.obj)
        @field_definitions = field_definitions
        @type_registry = type_registry
      end

      def json_schema
        JsonSchema.for_record_type(@field_definitions, @type_registry)
      end

      def construct(value)
        # Value should be a hash with the field values
        # Wrap raw values in appropriate Aua objects, with recursive casting for record types
        wrapped_values = {} # : Hash[String, Obj]

        value.each do |field_name, field_value|
          wrapped_values[field_name] = wrap_field_value(field_name, field_value)
        end

        # Create a structured object that supports member access
        Aua::RecordObject.new(@name, @field_definitions, wrapped_values)
      end

      private

      def wrap_field_value(field_name, field_value)
        # Find the field definition for this field
        field_def = @field_definitions.find { |fd| fd[:name] == field_name }

        # return @type_registry.wrap_value(field_value) unless field_def&.dig(:type, :type) == :type_reference
        return @type_registry.wrap_value(field_value) unless field_def && field_def[:type].type == :type_reference

        field_type_name = field_def[:type].value

        # Check if this field should be a record type
        return @type_registry.wrap_value(field_value) unless @type_registry.type?(field_type_name)

        field_type = @type_registry.lookup(field_type_name)

        # If it's a record type and we have a hash, recursively cast it
        if field_type.respond_to?(:field_definitions) && field_value.is_a?(Hash)
          field_type.construct(field_value)
        else
          # For non-record types or non-hash values, use regular wrapping
          @type_registry.wrap_value(field_value)
        end
      end
    end
  end
end
