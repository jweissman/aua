require_relative "ir/types"

module Aua
  module Runtime
    # Utility class to convert between AST, IR, and runtime type representations
    # This helps enforce the boundary so the VM never receives raw AST nodes
    class TypeConverter
      # Convert an AST type node to an IR type
      def self.ast_to_ir(ast_node)
        return IR::Types::TypeConstant.new(ast_node) unless ast_node.is_a?(AST::Node)

        Aua.logger.info("type-conv") do
          "Converting AST node #{ast_node.inspect} to IR type"
        end

        case ast_node.type
        when :type_reference
          IR::Types::TypeReference.new(ast_node.value)
        when :type_constant
          IR::Types::TypeConstant.new(ast_node.value)
        when :generic_type
          base_type, type_params = ast_node.value
          ir_params = type_params.map { |param| ast_to_ir(param) }
          IR::Types::GenericType.new(base_type, ir_params)
        when :record_type
          # Convert field definitions
          ir_fields = ast_node.value.map do |field|
            field_name = field.value[0]
            field_type_ir = ast_to_ir(field.value[1])
            { name: field_name, type: field_type_ir }
          end
          IR::Types::RecordType.new(ir_fields)
        when :union_type
          ir_variants = ast_node.value.map { |variant| ast_to_ir(variant) }
          IR::Types::UnionType.new(ir_variants)
        else
          raise Error, "Unknown AST type node: #{ast_node.type}"
        end
      end

      # Convert an IR type to a runtime type object
      def self.ir_to_runtime(ir_type, name, type_registry)
        case ir_type
        when IR::Types::TypeReference
          Runtime::Reference.new(name, ir_type.name)
        when IR::Types::TypeConstant
          Runtime::Constant.new(name, ir_type.name)
        when IR::Types::GenericType
          # Convert IR type params to runtime-appropriate format
          runtime_type_info = [ir_type.base_type, ir_type.type_params]
          Runtime::GenericType.new(name, runtime_type_info, type_registry)
        when IR::Types::RecordType
          Runtime::RecordType.new(name, ir_type.fields, type_registry)
        when IR::Types::UnionType
          Runtime::Union.new(name, ir_type.types, type_registry)
        else
          raise Error, "Unknown IR type: #{ir_type.class}"
        end
      end

      # One-step conversion from AST to runtime type
      def self.ast_to_runtime(ast_node, name, type_registry)
        ir_type = ast_to_ir(ast_node)
        ir_to_runtime(ir_type, name, type_registry)
      end

      # Convert an IR type to a string representation for annotations
      def self.ir_to_annotation_string(ir_type)
        case ir_type
        when IR::Types::TypeReference, IR::Types::TypeConstant
          ir_type.name
        when IR::Types::GenericType
          type_arg_strings = ir_type.type_params.map { |param| ir_to_annotation_string(param) }
          "#{ir_type.base_type}<#{type_arg_strings.join(", ")}>"
        when IR::Types::RecordType
          field_strings = ir_type.fields.map do |field|
            "#{field[:name]} => #{ir_to_annotation_string(field[:type])}"
          end
          "{ #{field_strings.join(", ")} }"
        when IR::Types::UnionType
          type_strings = ir_type.types.map { |type| ir_to_annotation_string(type) }
          type_strings.join(" | ")
        else
          ir_type.to_s
        end
      end
    end
  end
end
