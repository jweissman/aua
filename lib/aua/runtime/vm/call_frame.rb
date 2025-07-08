module Aua
  module Runtime
    # The virtual machine for executing Aua ASTs.
    class VM
      # Represents a call frame on the Aura call stack
      class CallFrame
        attr_reader :function_name, :parameters, :arguments, :local_env, :caller_env

        def initialize(function_name, parameters, arguments, caller_env)
          @function_name = function_name
          @parameters = parameters
          @arguments = arguments
          @caller_env = caller_env
          @local_env = caller_env.dup

          # Bind parameters to arguments in local environment
          parameters.zip(arguments) do |param, arg|
            @local_env[param] = arg
          end
        end

        def to_s
          args_str = @arguments.map(&:inspect).join(", ")
          "#{@function_name}(#{args_str})"
        end
      end
    end
  end
end
