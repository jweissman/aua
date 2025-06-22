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

        # Construct a list/array from elements.
        CONS = lambda do |elements|
          Semantics.inst(:cons, *elements)
        end
      end

      # The translator class that converts Aua AST nodes into VM instructions.
      class Translator
        include Commands

        def initialize(virtual_machine)
          @vm = virtual_machine
        end

        def environment = @vm.instance_variable_get(:@env)

        def translate(ast)
          case ast.type
          when :nihil, :int, :float, :bool, :simple_str, :str then reify_primary(ast)
          when :if, :negate, :id, :assign, :binop then translate_basic(ast)
          when :gen_lit then translate_gen_lit(ast)
          when :call then translate_call(ast)
          when :seq then translate_sequence(ast)
          when :structured_str, :structured_gen_lit then translate_structured_str(ast)
          when :type_declaration then translate_type_declaration(ast)
          when :object_literal then translate_object_literal(ast)
          when :array_literal then translate_array_literal(ast)
          else
            raise Error, "Unknown AST node type: \\#{ast.type}"
          end
        end

        # Join all parts, recursively translating expressions
        def translate_structured_str(node)
          parts = node.value.map { |part| translate_structured_str_part(part) }
          if node.type == :structured_gen_lit
            [GEN[CONCATENATE[parts]]]
          else
            [CONCATENATE[parts]]
          end
        end

        def translate_structured_str_part(part)
          Aua.logger.info "Translating part: \\#{part.inspect}"
          if part.is_a?(AST::Node)
            val = translate(part)
            val = val.first if val.is_a?(Array) && val.size == 1
            val.is_a?(Str) ? val.value : val
          else
            part.to_s
          end
        end

        def translate_call(node)
          fn_name, args = node.value
          [Semantics.inst(:call, fn_name, *args.map { |a| translate(a) })]
        end

        def translate_type_declaration(node)
          # Type declarations return the type declaration statement
          type_name, type_def = node.value
          [Statement.new(type: :type_declaration, value: [type_name, type_def])]
        end

        def translate_object_literal(node)
          # Translate each field value to statements
          translated_fields = {} # : Hash[String, untyped]

          # node.value is an array of field nodes
          node.value.each do |field_node|
            field_name, field_ast = field_node.value
            translated_field = translate(field_ast)
            translated_fields[field_name] = translated_field
          end

          [Statement.new(type: :object_literal, value: translated_fields)]
        end

        def translate_array_literal(node)
          # Translate each element in the array
          translated_elements = node.value.map { |element| translate(element) }
          [CONS[translated_elements]]
        end

        def translate_sequence(node)
          stmts = node.value
          Aua.logger.info("vm:tx") { "Translating sequence: #{stmts.inspect}" }
          raise Error, "Empty sequence" if stmts.empty?
          raise Error, "Sequence must be an array" unless stmts.is_a?(Array)
          raise Error, "Sequence must contain only AST nodes" unless stmts.all? { |s| s.is_a?(AST::Node) }

          stmts.map { |stmt| translate(stmt) }.flatten
        end

        def translate_basic(node)
          case node.type
          when :if then translate_if(node)
          when :negate then translate_negation(node)
          when :id then [LOCAL_VARIABLE_GET[node.value]]
          when :assign then translate_assignment(node)
          when :binop then translate_binop(node)
          else
            raise Error, "Unknown Basic AST node type: \\#{node.type}"
          end
        end

        def reify_primary(node)
          case node.type
          when :int then Int.new(node.value)
          when :float then Float.new(node.value)
          when :bool then Bool.new(node.value)
          when :str, :simple_str
            Aua.logger.info "Reifying string: #{node.inspect}"
            Str.new(node.value)
          else
            Aua.logger.warn "Unknown primary node type: #{node.type.inspect}"
            Nihil.new
          end
        end

        def translate_gen_lit(node)
          value = node.value
          current_conversation = Aua::LLM.chat
          [Str.new(current_conversation.ask(value))]
        end

        def translate_if(node)
          condition, true_branch, false_branch = node.value
          [
            Semantics.inst(:if, translate(condition), translate(true_branch), translate(false_branch))
          ]
        end

        def translate_negation(node)
          operand = node.value

          negated = case operand.type
                    when :int then Int.new(-operand.value)
                    when :float then Float.new(-operand.value)
                    else
                      raise Error, "Negation only supported for Int and Float"
                    end
          [RECALL[negated]]
        end

        def translate_assignment(node)
          name, value_node = node.value
          value = translate(value_node)
          [Semantics.inst(:let, name, value)]
        end

        def translate_binop(node)
          Aua.logger.info "Translating binop: #{node.inspect}"
          op, left_node, right_node = node.value

          # Special handling for member access - don't translate the right side
          if op == :dot
            left = translate(left_node)
            # Right side should be an ID node representing the field name
            unless right_node.type == :id
              raise Error, "Right side of member access must be a field name, got #{right_node.inspect}"
            end

            field_name = right_node.value
            return Binop.binary_operation(op, left, field_name)
          end

          left = translate(left_node)
          right = translate(right_node)
          Binop.binary_operation(op, left, right) || SEND[left, op, right]
        end

        # Support translating binary operations.
        module Binop
          class << self
            include Commands

            def binary_operation(operator, left, right)
              case operator
              when :plus then binop_plus(left, right)
              when :minus then binop_minus(left, right)
              when :star then binop_star(left, right)
              when :slash then binop_slash(left, right)
              when :pow then binop_pow(left, right)
              when :dot then [Statement.new(type: :member_access, value: [left, right])]
              when :as then handle_type_cast(left, right)
              else
                raise Error, "Unknown binary operator: #{operator}"
              end
            end

            private

            def handle_type_cast(left, right)
              Aua.logger.info "Type casting: #{left.inspect} as #{right.inspect}"

              # Unwrap rhs until we get a single value
              right = right.first while right.is_a?(Array) && right.size == 1

              Aua.logger.info("binary_operation") { "Aua vm env => #{Aua.vm.instance_variable_get(:@env).inspect}" }

              klass = resolve_cast_target(right)
              CAST[left, klass]
            end

            def resolve_cast_target(right)
              if right.is_a?(Klass)
                right
              elsif right.is_a?(Statement) && right.type == :id
                # Defer type lookup to execution time by creating a special statement
                Statement.new(type: :type_lookup, value: right.value.first)
              else
                Aua::Str.klass
              end
            end

            public

            def binop_plus(left, right)
              return int_plus(left, right) if left.is_a?(Int) && right.is_a?(Int)
              return float_plus(left, right) if left.is_a?(Float) && right.is_a?(Float)
              return str_plus(left, right) if left.is_a?(Str) && right.is_a?(Str)

              raise_binop_type_error(:+, left, right)
            end

            def int_plus(left, right)
              Int.new(left.value + right.value)
            end

            def float_plus(left, right)
              Float.new(left.value + right.value)
            end

            def str_plus(left, right)
              Str.new(left.value + right.value)
            end

            def raise_binop_type_error(operator, left, right)
              [SEND[left, operator, right]]
            end

            def binop_minus(left, right)
              if left.is_a?(Int) && right.is_a?(Int)
                Int.new(left.value - right.value)
              elsif left.is_a?(Float) && right.is_a?(Float)
                Float.new(left.value - right.value)
              else
                raise_binop_type_error(:-, left, right)
              end
            end

            def binop_star(left, right)
              if left.is_a?(Int) && right.is_a?(Int)
                Int.new(left.value * right.value)
              elsif left.is_a?(Float) && right.is_a?(Float)
                Float.new(left.value * right.value)
              else
                raise_binop_type_error(:*, left, right)
              end
            end

            def binop_slash(left, right)
              return int_slash(left, right) if left.is_a?(Int) && right.is_a?(Int)
              return float_slash(left, right) if left.is_a?(Float) && right.is_a?(Float)

              raise_binop_type_error(:/, left, right)
            end

            def int_slash(left, right)
              raise Error, "Division by zero" if right.value.zero?

              Int.new(left.value / right.value)
            end

            def float_slash(left, right)
              lhs = left  # : Float
              rhs = right # : Float
              raise Error, "Division by zero" if rhs.value == 0.0

              Float.new(lhs.value / rhs.value)
            end

            def binop_pow(left, right)
              if left.is_a?(Int) && right.is_a?(Int)
                # Convert to float to handle potential precision issues
                result = left.value.to_f**right.value.to_f
                # Return as Int if it's a whole number, Float otherwise
                if result.finite? && result == result.round
                  Int.new(result.to_i)
                else
                  Float.new(result)
                end
              elsif left.is_a?(Float) && right.is_a?(Float)
                Float.new(left.value**right.value)
              else
                raise_binop_type_error(:**, left, right)
              end
            end

            def binop_dot(left, right)
              # Member access: object.field
              # Right side should be a field name (string)
              unless right.is_a?(String)
                raise Error, "Right side of member access must be a field name, got #{right.inspect}"
              end

              field_name = right # : String
              access_field(left, field_name)
            end

            # Helper method for field access
            def access_field(obj, field_name)
              case obj
              when ObjectLiteral, RecordObject
                obj.get_field(field_name)
              when Obj
                # Try to access field via Aura method dispatch
                unless obj.respond_to?(:aura_respond_to?) && obj.aura_respond_to?(field_name.to_sym)
                  raise Error, "Cannot access field '#{field_name}' on #{obj.class.name}"
                end

                obj.aura_send(field_name.to_sym)
              else
                raise Error, "Expected an object for member access, got: #{obj.inspect} (#{obj.class})"
              end
            end
          end
        end
      end

      extend Semantics

      def initialize(env = {})
        @env = env
        @tx = Translator.new(self)
        @type_registry = TypeRegistry.new
      end

      def builtins
        @builtins ||= {
          inspect: method(:builtin_inspect),
          rand: method(:builtin_rand),
          time: method(:builtin_time),
          say: method(:builtin_say),
          ask: method(:builtin_ask),
          chat: method(:builtin_chat),
          see_url: method(:builtin_see_url),
          cast: method(:builtin_cast)
        }
      end

      private

      def builtin_cast(obj, klass)
        raise Error, "cast requires two arguments" unless obj.is_a?(Obj) && klass.is_a?(Klass)
        raise Error, "Cannot cast to non-Klass: \\#{klass.inspect}" unless klass.is_a?(Klass)

        # Generic casting using LLM + JSON schema
        Aua.logger.info "Casting object: \\#{obj.inspect} to class: \\#{klass.inspect}"

        Aua.logger.debug "Casting with schema: \\#{obj.introspect} (#{obj.class}) => \\#{klass.introspect} (#{klass.class})"

        chat = Aua::LLM.chat
        ret = chat.with_json_guidance(schema_for(klass)) do
          chat.ask(build_cast_prompt(obj, klass))
        end
        Aua.logger.info "Response from LLM: \\#{ret.inspect}"

        value = JSON.parse(ret)["value"]
        result = klass.construct(value)
        Aua.logger.info "Cast result: \\#{result.inspect} (\\#{result.class})"
        result
      end

      def schema_for(klass)
        # All Klass objects should provide json_schema and construct methods
        schema = {
          name: klass.name,
          strict: "true",
          schema: {
            **klass.json_schema,
            required: ["value"]
          }
        }

        Aua.logger.warn "Using schema: \\#{schema.inspect} for class: \\#{klass.name}"

        schema
      end

      def build_cast_prompt(obj, klass)
        _base_prompt = <<~PROMPT
          You are an English-language runtime.
          Please provide a 'translation' of the given object in the requested type (#{klass.introspect}).
          This should be a forgiving and humanizing cast into the spirit of the target type.

          The object is '#{obj.introspect}'.
        PROMPT

        # Add context for union types
        # if klass.respond_to?(:union_values)
        #   possible_values = klass.union_values
        #   base_prompt + <<~ADDITIONAL

        #     This is a union type with these possible values:
        #     #{possible_values.map { |v| "- '#{v}'" }.join("\n")}

        #     Please select the most appropriate value from this list.
        #   ADDITIONAL
        # else
        #   base_prompt
        # end
      end

      def builtin_inspect(obj)
        Aua.logger.info "Inspecting object: \\#{obj.inspect}"
        raise Error, "inspect requires a single argument" unless obj.is_a?(Obj)

        Aua.logger.info "Object class: \\#{obj.class}"
        Str.new(obj.introspect)
      end

      def builtin_rand(max)
        Aua.logger.info "Generating random number... (max: \\#{max.inspect})"
        rng = Random.new
        max = max.is_a?(Int) ? max.value : 100 if max.is_a?(Obj)
        Aua.logger.info "Using max value: \\#{max}"
        Aua::Int.new(rng.rand(0..max))
      end

      def builtin_time(_args)
        Aua.logger.info "Current time: \\#{Time.now}"
        Aua::Time.now
      end

      def builtin_say(arg)
        value = arg
        raise Error, "say only accepts Str arguments, got \\#{value.class}" unless value.is_a?(Str)

        $stdout.puts value.value

        Aua::Nihil.new
      end

      def builtin_ask(question)
        question = question.aura_send(:to_s) if question.is_a?(Obj) && !question.is_a?(Str)
        raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

        Aua.logger.info "Asking question: \\#{question.value}"
        response = $stdin.gets
        Aua.logger.info "Response: \\#{response}"
        raise Error, "No response received" if response.nil?

        Str.new(response.chomp)
      end

      def builtin_chat(question)
        raise Error, "ask requires a single Str argument" unless question.is_a?(Str)

        q = question.value
        Aua.logger.info "Posing question to chat: \\#{q.inspect} (\\#{q.length} chars, \\#{q.class} => String)"
        current_conversation = Aua::LLM.chat
        response = current_conversation.ask(q)
        Aua.logger.debug "Response: \\#{response}"
        Aua::Str.new(response)
      end

      def builtin_see_url(url)
        Aua.logger.info "Fetching URL: #{url.inspect}"
        raise Error, "see_url requires a single Str argument" unless url.is_a?(Str)

        uri = URI(url.value)
        response = Net::HTTP.get_response(uri)
        handle_see_url_response(uri, response)
      end

      def handle_see_url_response(url, response)
        raise Error, "Failed to fetch URL: #{url} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        Aua.logger.debug "Response from #{url}: #{response.body}"
        Aua::Str.new(response.body)
      end

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

        raise Error, "Expected a Statement, got: #{stmt.inspect} (#{stmt.class})" unless stmt.is_a? Statement

        evaluate_one!(stmt)
      end

      def evaluate_one!(stmt)
        val = stmt.value

        case stmt.type
        when :id, :let, :send, :member_access then evaluate_simple(stmt)
        when :type_declaration then eval_type_declaration(val[0], val[1])
        when :object_literal then eval_object_literal(val)
        when :type_lookup then eval_type_lookup(val)
        when :cast then eval_call(:cast, [val[0], val[1]])
        when :gen then eval_call(:chat, [val])
        when :cat then eval_cat(val)
        when :cons then eval_cons(val)
        when :call
          fn_name, *args = val
          eval_call(fn_name, args.map { |a| evaluate_one(a) })
        when :if
          cond, true_branch, false_branch = val
          eval_if(cond, true_branch, false_branch)
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
        Aua.logger.info "Resolving object: #{obj.inspect}"
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

        unless receiver.is_a?(Obj) && receiver.aura_respond_to?(method)
          raise Error, "Unknown aura method '#{method}' for #{receiver.class}"
        end

        receiver.aura_send(method, *args)
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
        fn = Aua.vm.builtins[fn_name.to_sym]
        raise Error, "Unknown builtin: #{fn_name}" unless fn

        evaluated_args = [*args].map { |a| evaluate_one(a) }
        fn.call(*evaluated_args)
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
          evaluate_one(true_branch)
        elsif false_branch
          evaluate_one(false_branch)
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
        case obj
        when ObjectLiteral, RecordObject
          obj.get_field(field_name)
        else
          # Try to access field via Aura method dispatch
          unless obj.respond_to?(:aura_respond_to?) && obj.aura_respond_to?(field_name.to_sym)
            raise Error, "Cannot access field '#{field_name}' on #{obj.class.name}"
          end

          obj.aura_send(field_name.to_sym)
        end
      end
    end
  end
end
