module Aua
  module Runtime
    # The virtual machine for executing Aua ASTs.
    class VM
      module Commands
        include Semantics
        # Recall a local variable by its value.
        RECALL = lambda do |item|
          Semantics.inst(:let, Semantics::MEMO, item)
        end

        # Retrieve the value of a local variable by name.
        LOCAL_VARIABLE_GET = lambda do |name|
          Semantics.inst(:id, name)
        end

        # Aura send command to invoke a method on an object.
        SEND = lambda do |receiver, method, *args|
          Semantics.inst(:send, receiver, method, *args)
        end

        # Concatenate an array of parts into a single string.
        CONCATENATE = lambda do |parts|
          Semantics.inst(:cat, *parts)
        end

        # Generate a new object from a prompt.
        GEN = lambda do |prompt|
          Semantics.inst(:gen, prompt)
        end

        # Cast an object to a specific type.
        CAST = lambda do |obj, type|
          Semantics.inst(:cast, obj, type)
        end

        # Semantic equality comparison using LLM.
        SEMANTIC_FUZZY_EQ = lambda do |left, right|
          Semantics.inst(:semantic_fuzzy_eq, left, right)
        end

        # Construct a list/array from elements.
        CONS = lambda do |elements|
          Semantics.inst(:cons, *elements)
        end

        # Look up a type by name from the type registry/environment.
        LOOKUP_TYPE = lambda do |type_name|
          Semantics.inst(:lookup_type, type_name)
        end

        LAMBDA = lambda do |args, body|
          Semantics.inst(:defun, args, body)
        end
      end
    end
  end
end
