module Aua
  module Runtime
    # Represents a statement in Aua, which can be an assignment, expression, or control flow.
    class Statement < Data.define(:type, :value)
      def inspect
        "#{type.upcase} #{value.inspect}"
      end
    end
  end
end
