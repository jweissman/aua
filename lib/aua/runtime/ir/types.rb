module Aua
  module Runtime
    module IR
      # Intermediate representation types used during translation
      # These represent type information between parsing and runtime execution
      module Types
        # Type representation classes for the translator
        class UnionType
          attr_reader :types

          def initialize(types)
            @types = types
          end

          def inspect
            "IR::UnionType(#{@types.map(&:inspect).join(" | ")})"
          end
        end

        class TypeReference
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def inspect
            "IR::TypeRef(#{@name})"
          end
        end

        class TypeConstant
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def inspect
            "IR::TypeConst(#{@name})"
          end
        end

        class GenericType
          attr_reader :base_type, :type_params

          def initialize(base_type, type_params)
            @base_type = base_type
            @type_params = type_params
          end

          def inspect
            "IR::GenericType(#{@base_type}<#{@type_params.map(&:inspect).join(", ")}>)"
          end
        end

        class RecordType
          attr_reader :fields

          def initialize(fields)
            @fields = fields # Array of { name: String, type: IR::Type }
          end

          def inspect
            field_strings = @fields.map { |f| "#{f[:name]}: #{f[:type].inspect}" }
            "IR::RecordType({ #{field_strings.join(", ")} })"
          end
        end
      end
    end
  end
end
