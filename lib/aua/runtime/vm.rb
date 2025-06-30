require_relative "vm/commands"
require_relative "vm/types"
require_relative "vm/translator"
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

        Aua.logger.debug(
          "Casting with schema: \\#{obj.introspect} (#{obj.class}) => " \
          "\\#{klass.introspect} (#{klass.class})"
        )

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
        base_prompt = <<~PROMPT
          You are an English-language runtime.
          Please provide a 'translation' of the given object in the requested type (#{klass.introspect}).
          This should be a forgiving and humanizing cast into the spirit of the target type.

          The object is '#{obj.introspect}'.
        PROMPT

        # Add type-specific guidance
        # type_guidance = if klass.aura_respond_to?(:describe)
        #                   klass.aura_send(:describe)
        #                 else
        #                   "This is a #{klass.name} type. Please provide a value that fits this type."
        #                 end
        type_guidance = case klass.name
                        when "List"
                          <<~GUIDANCE

                            This is a List type. The result should be an array of strings.
                            If the input contains multiple items (like in brackets or comma-separated),
                            preserve them as separate array elements. If it's a single item, you can
                            still make it an array, but consider if it represents multiple conceptual items.
                          GUIDANCE
                        when "Bool"
                          <<~GUIDANCE

                            This is a Boolean type.
                            Return true for positive, affirmative, or 'yes-like' values
                            (like "yes", "true", "yep", "ok", "sure", etc.) and false for negative, dismissive,
                            or 'no-like' values (like null, false, or strings like "no", "nope", "nah", "never", etc.).
                          GUIDANCE
                        when "Int"
                          <<~GUIDANCE

                            This is an Integer type. Convert textual numbers to their numeric equivalents.
                            For example: "one" → 1, "twenty-three" → 23, etc.
                          GUIDANCE
                        when "Str"
                          <<~GUIDANCE

                            For numbers, you might use written-out forms (like "3.14" → "π", "1" → "one").
                          GUIDANCE
                        when "Nihil"
                          <<~GUIDANCE
                            This is a Nihil type, which represents the absence of value.
                            For instance, you might return an empty string.
                          GUIDANCE
                        else
                          ""
                        end

        # Add context for union types
        if klass.respond_to?(:union_values)
          possible_values = klass.union_values
          type_guidance += <<~ADDITIONAL

            This is a union type with these possible values:
            #{possible_values.map { |v| "- '#{v}'" }.join("\n")}

            Please select the most appropriate value from this list.
          ADDITIONAL
        end

        # base_prompt + type_guidance + "\n"
        [base_prompt, type_guidance].join("\n").strip
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
        $stdout.puts(question.value)
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
        when :type_lookup, :lookup_type then eval_type_lookup(val)
        when :union_type_lookup then eval_union_type_lookup(val)
        when :cast then eval_call(:cast, [val[0], val[1]])
        when :gen then eval_call(:chat, [val])
        when :cat then eval_cat(val)
        when :cons then eval_cons(val)
        when :dynamic_union_class then eval_dynamic_union_class(val)
        when :llm_select then eval_llm_select(val[0], val[1])
        when :collapse then eval_collapse(val[0], val[1])
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

        unless receiver.is_a?(Obj) && receiver.aura_respond_to?(method)
          raise Error, "Unknown aura method '#{method}' for #{receiver.class}"
        end

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
        fn = Aua.vm.builtins[fn_name.to_sym]
        raise Error, "Unknown builtin: #{fn_name}" unless fn

        evaluated_args = [*args].map { |a| evaluate_one(a) }
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
    end
  end
end
