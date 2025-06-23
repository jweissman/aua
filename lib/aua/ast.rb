# Aua is a programming language and interpreter written in Ruby...
module Aua
  # The AST (Abstract Syntax Tree) node definitions for Aua.
  module AST
    # Represents a node in the abstract syntax tree (AST) of Aua.
    class Node < Data.define(:type, :value, :at)
      def inspect = "#{type}(#{value.inspect})"

      def ==(other)
        return false unless other.is_a?(Node)

        type == other.type && value == other.value
      end
    end
  end
end
