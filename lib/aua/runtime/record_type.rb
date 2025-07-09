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
        return @type_registry.wrap_value(field_value) unless field_def

        field_type = field_def[:type]

        # Handle IR types (new approach)
        if field_type.is_a?(Aua::Runtime::IR::Types::TypeReference)
          handle_type_reference(field_type, field_value)
        elsif field_type.is_a?(Aua::Runtime::IR::Types::TypeConstant)
          # Handle built-in types like String, Int
          @type_registry.wrap_value(field_value)
        elsif field_type.is_a?(Aua::Runtime::IR::Types::GenericType)
          handle_ir_generic_type(field_type, field_value)
        # Legacy AST node support (fallback)
        elsif field_type.respond_to?(:type)
          handle_ast_field_type(field_type, field_value)
        else
          # For unknown field types, use regular wrapping
          @type_registry.wrap_value(field_value)
        end
      end

      def handle_type_reference(field_type, field_value)
        field_type_name = field_type.name

        # Check if this field should be a record type
        return @type_registry.wrap_value(field_value) unless @type_registry.type?(field_type_name)

        field_type_obj = @type_registry.lookup(field_type_name)

        # If it's a record type and we have a hash, recursively cast it
        if field_type_obj.respond_to?(:field_definitions) && field_value.is_a?(Hash)
          field_type_obj.construct(field_value)
        else
          # For non-record types or non-hash values, use regular wrapping
          @type_registry.wrap_value(field_value)
        end
      end

      def handle_ir_generic_type(field_type, field_value)
        base_type = field_type.base_type
        type_params = field_type.type_params

        # Create the wrapped value first
        wrapped_value = @type_registry.wrap_value(field_value)

        # Apply type annotation for generic types
        if base_type == "List" && wrapped_value.is_a?(Aua::List)
          # Generate type annotation string like "List<String>"
          type_arg_strings = type_params.map do |param|
            if param.respond_to?(:name)
              param.name
            else
              param.to_s
            end
          end
          type_annotation = "#{base_type}<#{type_arg_strings.join(", ")}>"
          wrapped_value.instance_variable_set(:@type_annotation, type_annotation)
        end

        wrapped_value
      end

      def handle_ast_field_type(field_type, field_value)
        case field_type.type
        when :type_reference
          field_type_name = field_type.value

          # Check if this field should be a record type
          return @type_registry.wrap_value(field_value) unless @type_registry.type?(field_type_name)

          field_type_obj = @type_registry.lookup(field_type_name)

          # If it's a record type and we have a hash, recursively cast it
          if field_type_obj.respond_to?(:field_definitions) && field_value.is_a?(Hash)
            field_type_obj.construct(field_value)
          else
            # For non-record types or non-hash values, use regular wrapping
            @type_registry.wrap_value(field_value)
          end
        when :generic_type
          # Handle generic types like List<String>
          base_type = field_type.value[0]
          type_args = field_type.value[1] || []

          # Create the wrapped value first
          wrapped_value = @type_registry.wrap_value(field_value)

          # Apply type annotation for generic types
          if base_type == "List" && wrapped_value.is_a?(Aua::List)
            # Generate type annotation string like "List<String>"
            type_arg_strings = type_args.map do |arg|
              case arg.type
              when :type_reference
                arg.value
              else
                arg.to_s
              end
            end
            type_annotation = "#{base_type}<#{type_arg_strings.join(", ")}>"
            wrapped_value.instance_variable_set(:@type_annotation, type_annotation)
          end

          wrapped_value
        else
          # For unknown field types, use regular wrapping (consolidate the fallback)
          @type_registry.wrap_value(field_value)
        end
      end
    end
  end
end
