module Aua
  module Runtime
    class VM
      module Types
        # Type representation classes for the translator
        class UnionType
          attr_reader :types

          def initialize(types)
            @types = types
          end

          def inspect
            "UnionType(#{@types.map(&:inspect).join(" | ")})"
          end
        end

        class TypeReference
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def inspect
            "TypeRef(#{@name})"
          end
        end

        class TypeConstant
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def inspect
            "TypeConst(#{@name})"
          end
        end
      end
    end
  end
end
