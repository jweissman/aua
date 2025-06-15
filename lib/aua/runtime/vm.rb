module Aua
  module Runtime
    # The virtual machine for executing Aua ASTs.
    class VM
      module Commands
        include Semantics
        RECALL = lambda do |item|
          Semantics.inst(:let, Semantics::MEMO, item)
        end

        LOCAL_VARIABLE_GET = lambda do |name|
          Semantics.inst(:id, name)
        end

        SEND = lambda do |receiver, method, *args|
          Semantics.inst(:send, receiver, method, *args)
        end

        CONCATENATE = lambda do |parts|
          # Concatenate an array of parts into a single string.
          # This is used for structured strings.
          Semantics.inst(:cat, *parts)
        end

        GEN = lambda do |prompt|
          Semantics.inst(:gen, prompt)
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

        def translate_sequence(node)
          stmts = node.value
          Aua.logger.info "Translating sequence: #{stmts.inspect}"
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
            warn "Unknown primary node type: #{node.type.inspect}"
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
              when :plus then Binop.binop_plus(left, right)
              when :minus then Binop.binop_minus(left, right)
              when :star then Binop.binop_star(left, right)
              when :slash then Binop.binop_slash(left, right)
              when :pow then Binop.binop_pow(left, right)
              else
                raise Error, "Unknown binary operator: #{operator}"
              end
            end

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
                Int.new(
                  left.value**right.value # : Integer
                )
              elsif left.is_a?(Float) && right.is_a?(Float)
                Float.new(left.value**right.value)
              else
                # raise Error, "Unsupported operand types for **: #{left.class} and #{right.class}"
                raise_binop_type_error(:**, left, right)
              end
            end
          end
        end
      end

      extend Semantics

      def initialize(env = {})
        @env = env
        @tx = Translator.new(self)
      end

      def builtins
        @builtins ||= {
          inspect: method(:builtin_inspect),
          rand: method(:builtin_rand),
          time: method(:builtin_time),
          say: method(:builtin_say),
          ask: method(:builtin_ask),
          chat: method(:builtin_chat),
          see_url: method(:builtin_see_url)
        }
      end

      private

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

        puts arg.value
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

      def evaluate(_ctx, ast)
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
        when :id, :let, :send then evaluate_simple(stmt)
        when :gen then eval_call(:chat, [val])
        when :cat then eval_cat(val)
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

      def eval_call(fn_name, args)
        fn = Aua.vm.builtins[fn_name.to_sym]
        raise Error, "Unknown builtin: #{fn_name}" unless fn

        evaluated_args = [*args].map { |a| evaluate_one(a) }
        fn.call(*evaluated_args)
      end

      def eval_id(identifier)
        identifier = identifier.first if identifier.is_a?(Array)
        Aua.logger.info "Getting variable #{identifier}"
        raise Error, "Undefined variable: #{identifier}" unless @env.key?(identifier)

        @env[identifier]
      end

      def eval_let(name, value)
        Aua.logger.info "Setting variable #{name} to #{value.inspect}"
        @env[name] = value
        value
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
    end
  end
end
