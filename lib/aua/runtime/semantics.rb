module Aua
  module Runtime
    # Semantic helpers for statements and let bindings.
    module Semantics
      MEMO = "_".freeze
      def self.inst(type, *args)
        Statement.new(type:, value: args)
      end
    end
  end
end
