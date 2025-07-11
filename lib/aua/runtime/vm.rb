require_relative "vm/commands"
require_relative "vm/types"
require_relative "vm/translator"
require_relative "vm/call_frame"
require_relative "vm/builtin"
require_relative "type_classes"

module Aua
  module Runtime
    # The virtual machine for executing Aua ASTs.
    class VM
      extend Semantics
      def initialize(env = {})
        @env = env
        @tx = Translator.new(self)
        @type_registry = TypeRegistry.new
        @call_stack = [] # Stack of CallFrame objects
        @max_stack_depth = 1000 # Prevent stack overflow
      end

      def builtins
        @builtins ||= {
          inspect: Builtin.method(:builtin_inspect),
          rand: Builtin.method(:builtin_rand),
          time: Builtin.method(:builtin_time),
          say: Builtin.method(:builtin_say),
          ask: Builtin.method(:builtin_ask),
          chat: Builtin.method(:builtin_chat),
          see_url: Builtin.method(:builtin_see_url),
          cast: Builtin.method(:builtin_cast),
          typeof: Builtin.method(:builtin_typeof)
        }
      end

      private

      def reduce(ast) = @tx.translate(ast)

      def evaluate(_ctx, ast) = evaluate!(ast)

      def evaluate!(ast)
        ret = Nihil.new
        stmts = reduce(ast)
        stmts = [stmts] unless stmts.is_a? Array
        stmts.each do |stmt|
          ret = stmt.is_a?(Obj) ? stmt : evaluate_one(stmt)
        end
        evaluate_one Commands::RECALL[ret]
        ret
      end

      # Evaluates a single statement in the VM.
      # - Unwrap arrays of length 1 until we get a Statement
      # - Resolve objects to their final form
      def evaluate_one(stmt)
        stmt = stmt.first while stmt.is_a?(Array) && stmt.size == 1
        return resolve(stmt) if stmt.is_a? Obj

        raise Error, "Expected a Statement, got: #{stmt.inspect[...80]}... (#{stmt.class})" unless stmt.is_a? Statement

        evaluate_one!(stmt)
      end

      def evaluate_one!(stmt)
        return stmt if stmt.is_a?(Aua::Obj)

        val = stmt.value

        case stmt.type
        when :id, :let, :send, :member_access then evaluate_simple(stmt)
        when :member_assignment then eval_member_assignment(val[0], val[1], val[2])
        when :type_declaration then eval_type_declaration(val[0], val[1])
        when :function_definition then eval_function_definition(val)
        when :defun then eval_defun(val)
        when :object_literal then eval_object_literal(val)
        when :type_lookup, :lookup_type then eval_type_lookup(val)
        when :generic_type_lookup then eval_generic_type_lookup(val)
        when :union_type_lookup then eval_union_type_lookup(val)
        when :cast then eval_call(:cast, [val[0], val[1]])
        when :gen then eval_call(:chat, [val])
        when :cat then eval_cat(val)
        when :cons then eval_cons(val)
        when :dynamic_union_class then eval_dynamic_union_class(val)
        when :llm_select then eval_llm_select(val[0], val[1])
        when :collapse then eval_collapse(val[0], val[1])
        when :typed_value then eval_typed_value(val[0], val[1])
        when :call
          fn_name, *args = val
          eval_call(fn_name, args.map { |a| evaluate_one(a) })
        when :if
          cond, true_branch, false_branch = val
          eval_if(cond, true_branch, false_branch)
        when :while
          cond, body = val
          eval_while(cond, body)
        else
          raise Error, "Unknown statement: #{stmt} (#{stmt.class})"
        end
      end

      def evaluate_simple(stmt)
        val = stmt.value
        case stmt.type
        when :id then eval_id(val)
        when :let then eval_let(val[0], evaluate_one(val[1]))
        when :send then eval_send(val[0], val[1], *val[2..])
        when :member_access then eval_member_access(val[0], val[1])
        else

          raise Error, "Unknown simple statement: #{stmt} (#{stmt.class})"
        end
      end

      # interpolate strings, collapse complex vals, etc.
      def resolve(obj)
        Aua.logger.debug("vm:resolve") { "Resolving object: #{obj.inspect}" }
        return interpolated(obj) if obj.is_a?(Str)

        obj
      end

      def interpolated(obj)
        return obj unless obj.is_a?(Str)

        Aua.logger.info "Interpolating string: #{obj.inspect}"
        Aua.vm.builtins[:inspect]
        obj
      end

      def eval_send(receiver, method, *args)
        receiver = evaluate_one(
          receiver # : Statement
        )
        args = args.map do |arg|
          evaluate_one(
            arg # : Statement
          )
        end

        raise Error, "Unknown aura method '#{method}' for #{receiver.class}" unless receiver.aura_respond_to?(method)

        ret = receiver.aura_send(method, *args)
        Aua.logger.info("vm:eval_send") do
          "Sending method '#{method}' to #{receiver.class} with args: #{args.inspect} => #{ret.inspect}"
        end
        ret
      end

      def eval_cat(parts)
        parts = parts.map do |part|
          part.is_a?(String) ? part : to_ruby_str(evaluate_one(part))
        end

        # Concatenate all parts into a single string
        Str.new(parts.join)
      end

      def eval_cons(elements)
        # Evaluate each element and create a List object
        evaluated_elements = elements.map { |element| evaluate_one(element) }
        List.new(evaluated_elements)
      end

      def eval_call(fn_name, args)
        # First check if it's a user-defined function (Function object)
        return eval_user_function(@env[fn_name], args) if @env.key?(fn_name) && @env[fn_name].is_a?(Aua::Function)

        # Check for legacy hash-based functions (for backward compatibility)
        if @env.key?(fn_name) && @env[fn_name].is_a?(Hash) && @env[fn_name][:type] == :user_function
          return eval_user_function(@env[fn_name], args)
        end

        # Fall back to builtin functions
        fn = Aua.vm.builtins[fn_name.to_sym]
        raise Aua::Error, "Unknown function: #{fn_name}" unless fn

        evaluated_args = [*args].map { |a| evaluate_one(a) }

        arity_match = fn.arity == evaluated_args.size || (fn.arity < 0 && evaluated_args.size >= -fn.arity)
        unless arity_match
          raise Aua::Error,
                "Wrong number of arguments for #{fn_name}: expected #{fn.arity}, got #{evaluated_args.size}"
        end

        ret = fn.call(*evaluated_args)
        Aua.logger.info("vm:eval_call") do
          "Calling builtin function: #{fn_name} with args: #{args.inspect} => #{ret.inspect}"
        end
        ret
      end

      def eval_id(identifier)
        identifier = identifier.first if identifier.is_a?(Array)
        Aua.logger.info("vm:eval_id") { "Getting variable #{identifier}" }
        raise Error, "Undefined variable: #{identifier}" unless @env.key?(identifier)

        @env[identifier]
      end

      def eval_let(name, value)
        if value.is_a?(AST::Node)
          val = value # : AST::Node
          value = evaluate!(val)
        end
        @env[name] = resolve(value)
        value
      end

      def eval_type_declaration(name, type_definition)
        # Register the type in our type registry
        @type_registry.register(name, type_definition)

        # Also add it to the environment so it can be referenced
        type_obj = @type_registry.lookup(name)
        @env[name] = type_obj

        # Return the type object
        type_obj
      end

      def eval_type_lookup(type_name)
        # Look up a type by name in the type registry
        type_obj = @type_registry.lookup(type_name)
        if type_obj.nil?
          # Also check the environment for built-in types
          type_obj = @env[type_name]
        end

        raise Error, "Type '#{type_name}' not found" unless type_obj

        type_obj
      end

      def eval_union_type_lookup(type_name)
        # Look up a union type and convert it to a dynamic union class
        type_obj = @type_registry.lookup(type_name)
        type_obj = @env[type_name] if type_obj.nil?

        raise Error, "Type '#{type_name}' not found" unless type_obj

        # Extract choices from the union type and create dynamic class
        choices = extract_union_choices_from_type(type_obj)
        eval_dynamic_union_class(choices)
      end

      def extract_union_choices_from_type(type_obj)
        # Handle different ways union types might be stored
        if type_obj.respond_to?(:union_values)
          # This is a proper Union class from type_classes.rb
          type_obj.union_values
        elsif type_obj.respond_to?(:choices)
          type_obj.choices
        elsif type_obj.is_a?(UnionType)
          # Extract choices from UnionType
          type_obj.types.map do |type_const|
            if type_const.is_a?(TypeConstant)
              type_const.name
            else
              type_const.inspect
            end
          end
        else
          # Fallback - assume it's a simple type
          [type_obj.inspect]
        end
      end

      def eval_object_literal(translated_fields)
        # translated_fields is a hash where keys are field names (strings)
        # and values are translated statements (arrays of statements)
        values = {} # : Hash[String, Obj]
        translated_fields.each do |field_name, field_statements|
          # Evaluate the field's statements to get the actual value
          # For single field values, field_statements should be an array with one element
          field_value = if field_statements.is_a?(Array)
                          field_statements.map { |stmt| evaluate_one(stmt) }.last
                        else
                          evaluate_one(field_statements)
                        end
          values[field_name] = field_value
        end

        # Return an ObjectLiteral instance
        ObjectLiteral.new(values)
      end

      def eval_if(condition, true_branch, false_branch)
        condition_value = evaluate_one(condition)
        if condition_value.is_a?(Bool) && condition_value.value
          eval_branch(true_branch)
        elsif false_branch
          eval_branch(false_branch)
        end
      end

      def eval_branch(branch)
        case branch
        when Array
          # Handle array of statements - evaluate each and return the last result
          result = nil
          branch.each { |stmt| result = evaluate_one(stmt) }
          result
        else
          # Handle single statement
          evaluate_one(branch)
        end
      end

      def to_ruby_str(maybe_str)
        case maybe_str
        when String
          maybe_str
        when Str
          maybe_str.value
        when Obj
          Aua.logger.info "Converting object to string: #{maybe_str.inspect}"
          maybe_str.aura_send(:to_s)
        else
          raise Error, "Cannot concatenate non-string object: #{maybe_str.inspect}"
        end
      end

      def eval_member_access(obj_statements, field_name)
        # Evaluate the object (left side of the dot)
        obj = if obj_statements.is_a?(Array)
                obj_statements.map { |stmt| evaluate_one(stmt) }.last
              else
                evaluate_one(obj_statements)
              end

        # Access the field
        field_value = case obj
                      when ObjectLiteral, RecordObject
                        obj.get_field(field_name)
                      else
                        # Try to access field via Aura method dispatch
                        unless obj.respond_to?(:aura_respond_to?) && obj.aura_respond_to?(field_name.to_sym)
                          raise Error, "Cannot access field '#{field_name}' on #{obj.class.name}"
                        end

                        obj.aura_send(field_name.to_sym)
                      end

        # Propagate type annotation from struct definition if available
        if obj.instance_variable_defined?(:@type_annotation) && obj.instance_variable_get(:@type_annotation)
          parent_type = obj.instance_variable_get(:@type_annotation)
          field_type = get_field_type_from_struct(parent_type, field_name)
          field_value.instance_variable_set(:@type_annotation, field_type) if field_type
        end

        field_value
      end

      def eval_member_assignment(obj_name, field_name, value_statements)
        # Evaluate the value to assign
        new_value = if value_statements.is_a?(Array)
                      value_statements.map { |stmt| evaluate_one(stmt) }.last
                    else
                      evaluate_one(value_statements)
                    end

        # Get the current object from the environment
        raise Error, "Variable '#{obj_name}' not found" unless @env.key?(obj_name)

        current_obj = @env[obj_name]

        # Handle different object types - create NEW object, don't mutate original
        case current_obj
        when ObjectLiteral, RecordObject
          # Check if the field exists (for type safety)
          raise Error, "Field '#{field_name}' not found in object type" unless current_obj.has_field?(field_name)

          # Basic type checking - compare the type of the new value with the existing field
          existing_value = current_obj.get_field(field_name)
          if existing_value && !compatible_types?(existing_value, new_value)
            raise Error,
                  "Type mismatch: cannot assign #{type_name(new_value)} to field '#{field_name}' expecting #{type_name(existing_value)}"
          end

          # Create a new object with the updated field (or mutate if that's what set_field does)
          current_obj.set_field(field_name, new_value)
        else
          raise Error,
                "Cannot assign to field '#{field_name}' on #{current_obj.class.name} - not an object"
        end

        # DON'T update the original variable - this should be functional/immutable
        # @env[obj_name] = updated_obj  # <-- Remove this line for functional behavior

        # Return the NEW object (but original variable remains unchanged)
      end

      def eval_while(condition, body)
        # While loops return nihil (null/void) like in most languages
        result = resolve(Nihil.new)

        # Loop while condition is true
        loop do
          condition_result = evaluate_one(condition)

          # Convert to boolean - truthy check
          is_truthy = case condition_result
                      when Bool then condition_result.value
                      when Nihil then false
                      when Int then condition_result.value != 0
                      when Str then !condition_result.value.empty?
                      else true
                      end

          break unless is_truthy

          # Execute the body
          eval_branch(body)
        end

        result
      end

      def eval_llm_select(prompt_text, choices)
        Aua.logger.info("vm:eval_llm_select") { "LLM selection: '#{prompt_text}' from #{choices.inspect}" }

        # For now, simulate LLM selection with simple text matching
        # In practice, this would call out to an actual LLM service
        prompt_lower = prompt_text.downcase

        # Simple heuristics to select the most appropriate choice
        best_choice = choices.find do |choice|
          choice_str = choice.is_a?(Str) ? choice.value : choice.to_s
          prompt_lower.include?(choice_str.downcase)
        end

        # If no direct match, try partial matching
        if best_choice.nil?
          best_choice = choices.find do |choice|
            choice_str = choice.is_a?(Str) ? choice.value : choice.to_s
            choice_str.downcase.split(/[^a-z]/).any? { |word| prompt_lower.include?(word) }
          end
        end

        # Fallback: return first choice if no match found
        best_choice ||= choices.first

        # Convert to Aua::Str if needed
        result = if best_choice.is_a?(Str)
                   best_choice
                 else
                   Str.new(best_choice.to_s)
                 end

        Aua.logger.info("vm:eval_llm_select") { "Selected: #{result.value}" }
        result
      end

      def eval_dynamic_union_class(choices)
        Aua.logger.info("vm:eval_dynamic_union_class") do
          "Creating dynamic union class with choices: #{choices.inspect}"
        end

        # Create type_constant variants for each choice
        # We need to create AST::Node-like structures that the Union class expects
        variants = choices.map do |choice|
          # Create a type_constant variant with a proper value node
          value_node = Struct.new(:value).new(choice)
          Struct.new(:type, :value).new(:type_constant, value_node)
        end

        # Use the existing Union class instead of metaprogramming
        Union.new("DynamicUnion", variants, @type_registry)
      end

      def eval_function_definition(function_data)
        # Function definition stores the function in the environment
        function_name = function_data[:name]
        parameters = function_data[:parameters]
        body = function_data[:body]

        # Create Function object
        function_obj = Aua::Function.new(name: function_name, parameters:, body:)

        # Store the function in the current environment
        @env[function_name] = function_obj

        function_obj.enclose(@env)

        # Return the function object
        function_obj
      end

      def eval_defun(val)
        args, body = val

        # Extract parameter names from the args
        parameters = case args
                     when Array
                       if args.length == 1 && args.first.is_a?(Aua::Runtime::Statement) && args.first.type == :cons
                         # This is a CONS [param1, param2, ...] - extract parameters from the CONS value
                         cons_statement = args.first
                         param_nodes = cons_statement.value # Array of parameter nodes
                         param_nodes.map { |node| extract_parameter_name(node) }
                       else
                         # Regular array of parameter declarations
                         args.map { |arg| extract_parameter_name(arg) }
                       end
                     else
                       # Single parameter
                       [extract_parameter_name(args)]
                     end

        # Create a Function object with a generated name for anonymous functions
        function_name = "lambda_#{object_id}_#{rand(1000)}"

        # Create the function object with current environment as closure
        Aua::Function.new(name: function_name, parameters: parameters, body: body)
                     .enclose(@env)
      end

      def extract_parameter_name(arg)
        # Unwrap single-element arrays (common wrapping pattern in AST)
        arg = arg.first if arg.is_a?(Array) && arg.length == 1

        case arg
        when Array
          # Handle ID node format: ["ID", ["param_name"]] or [:ID, ["param_name"]]
          if (["ID", :ID].include?(arg.first) || arg.first.to_s == "ID") && arg.last.is_a?(Array)
            arg.last.first # Extract the parameter name
          else
            arg.to_s # Fallback for unexpected array formats
          end
        when ->(a) { a.respond_to?(:type) && a.type == :id && a.respond_to?(:value) }
          # Handle Statement objects with :id type
          arg.value.first
        else
          # Fallback for other types
          arg.to_s
        end
      end

      def eval_user_function(function_obj, args)
        return unless function_obj.is_a?(Aua::Function)

        eval_function_object(function_obj, args)
      end

      def eval_function_object(function_obj, args)
        # Extract function information from Function object
        function_name = function_obj.name
        parameters = function_obj.parameters
        body = function_obj.body
        closure_env = function_obj.closure_env

        # Check argument count
        if args.length != parameters.length
          raise Error, "Function '#{function_name}' expects #{parameters.length} arguments, got #{args.length}"
        end

        # Check for stack overflow
        if @call_stack.length >= @max_stack_depth
          stack_trace = @call_stack.map(&:to_s).join(" -> ")
          raise Error, "Stack overflow: maximum call depth (#{@max_stack_depth}) exceeded\nCall stack: #{stack_trace}"
        end

        # Evaluate arguments in current environment
        evaluated_args = args.map { |arg| evaluate_one(arg) }

        # Create and push new call frame
        frame = CallFrame.new(function_name, parameters, evaluated_args, closure_env)
        @call_stack.push(frame)

        # Switch to frame's local environment
        previous_env = @env
        @env = frame.local_env

        begin
          # Execute function body
          result = eval_branch(body)
          result
        ensure
          # Restore previous environment and pop call frame
          @env = previous_env
          @call_stack.pop
        end
      end

      # Type checking helpers for member assignment
      def compatible_types?(existing_value, new_value)
        # Simple type compatibility check based on class
        existing_value.class == new_value.class
      end

      def type_name(value)
        case value
        when Int then "Int"
        when Str then "Str"
        when Bool then "Bool"
        when Float then "Float"
        else value.class.name.split("::").last
        end
      end

      def eval_typed_value(value_stmt, type_stmt)
        # Evaluate the value first
        value = evaluate_one(value_stmt)

        # Handle type annotations for different object types
        if value.is_a?(Aua::List) || value.is_a?(Aua::ObjectLiteral) || value.is_a?(Aua::Dict)
          type_annotation = nil

          # Handle direct generic types: List<String>, Dict<String, Int>
          if type_stmt.is_a?(Array) && type_stmt.first.is_a?(Aua::Runtime::VM::Types::GenericType)
            generic_type = type_stmt.first
            type_annotation = "#{generic_type.base_type}<#{generic_type.type_params.map(&:name).join(", ")}>"

            # Convert ObjectLiteral to Dict if the type is a Dict type
            if value.is_a?(Aua::ObjectLiteral) && generic_type.base_type == "Dict"
              value = Aua::Dict.new(value.values, type_annotation)
            end

          # Handle type references that might resolve to generic types: BookList
          elsif type_stmt.is_a?(Array) && type_stmt.first.is_a?(Aua::Runtime::VM::Types::TypeReference)
            type_ref = type_stmt.first
            # Look up the type in the registry
            resolved_type = @type_registry.lookup(type_ref.name)
            if resolved_type.is_a?(Aua::Runtime::GenericType)
              # Extract type arg names from AST nodes
              type_arg_names = resolved_type.type_args.map { |arg| describe_type_ast(arg) }
              # debugger
              type_annotation = "#{resolved_type.base_type}<#{type_arg_names.join(", ")}>"

              # Convert ObjectLiteral to List if the type is a List type
              if value.is_a?(Aua::ObjectLiteral) && resolved_type.base_type == "List"
                # Convert empty object literal {} to empty list []
                value = Aua::List.new([])
              # Convert ObjectLiteral to Dict if the type is a Dict type
              elsif value.is_a?(Aua::ObjectLiteral) && resolved_type.base_type == "Dict"
                value = Aua::Dict.new(value.values, type_annotation)
              end
            else
              type_annotation = type_ref.name
            end
          end

          value.instance_variable_set(:@type_annotation, type_annotation) if type_annotation
        end

        value
      end

      def eval_generic_type_lookup(generic_info)
        # Handle generic type lookup like List<String>
        # generic_info is a hash with { base: "List", args: [TypeRef(String)] }
        base_type = generic_info[:base]
        type_args = generic_info[:args]

        # Create a concrete GenericType instance that can be used for casting
        # The GenericType class from type_classes.rb expects (name, type_info, type_registry)
        type_info = [base_type, type_args]
        generic_type = Aua::Runtime::GenericType.new("#{base_type}<...>", type_info, @type_registry)

        # Update the name to use the proper introspect method
        generic_type.instance_variable_set(:@name, generic_type.introspect)

        generic_type
      end

      # def eval_generic_type_cast(generic_type)
      #   # Handle casting to generic types like List<String>
      #   # For now, we'll return the base type's class (e.g., List.klass for List<String>)

      #   case generic_type.base_type
      #   when "List"
      #     Aua::List.klass
      #   when "Dict"
      #     Aua::Dict.klass
      #   else
      #     # Default to string for unknown generic types
      #     Aua::Str.klass
      #   end
      # end

      def get_field_type_from_struct(struct_type_name, field_name)
        # Look up the struct definition in the type registry
        struct_def = @type_registry.lookup(struct_type_name)
        return nil unless struct_def

        # Handle different types of struct definitions
        case struct_def
        when Aua::Runtime::RecordType
          # Find the field in the record type field definitions
          field_def = struct_def.field_definitions.find { |fd| fd[:name] == field_name }
          return nil unless field_def

          # Convert the field type to a string representation
          convert_type_to_annotation_string(field_def[:type])
        else
          nil
        end
      end

      def convert_type_to_annotation_string(type_obj)
        case type_obj
        when Aua::Runtime::VM::Types::TypeReference
          type_obj.name
        when Aua::Runtime::VM::Types::GenericType
          # Build the generic type string like "List<String>"
          type_arg_strings = type_obj.type_params.map { |param| convert_type_to_annotation_string(param) }
          "#{type_obj.base_type}<#{type_arg_strings.join(", ")}>"
        when Aua::AST::Node
          # Handle AST nodes from struct definitions using describe_type_ast
          describe_type_ast(type_obj)
        else
          type_obj.to_s
        end
      end

      def describe_type_ast(node)
        case node.type
        when :record_type
          introspection = "{ " + node.value.to_h(&method(:describe_type_ast)).map { |k, v|
            "#{k} => #{v}"
          }.join(", ") + " }"
          if introspection.length > 80
            "{...}"
          else
            introspection
          end
        when :generic_type
          # Handle generic types like List<String>
          base_type = node.value[0]
          type_args = node.value[1] || []
          type_arg_strings = type_args.map { |arg| describe_type_ast(arg) }
          "#{base_type}<#{type_arg_strings.join(", ")}>"
        when :field then [node.value[0], describe_type_ast(node.value[1])] # Field type is the second element
        when :type_reference then node.value
        else
          Aua.logger.warn("vm:describe_type_ast") do
            "Unknown AST node type for type description: #{node.type} - using value: #{node.value.inspect}"
          end
          # For other types, just return the value as a string
          node.value.to_s
        end
      end
    end
  end
end
