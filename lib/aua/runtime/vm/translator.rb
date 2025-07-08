module Aua
  module Runtime
    # The virtual machine for executing Aua ASTs.
    class VM
      # The translator class that converts Aua AST nodes into VM instructions.
      class Translator
        include IR::Types
        include Commands

        def initialize(virtual_machine)
          @vm = virtual_machine
        end

        def environment = @vm.instance_variable_get(:@env)

        def translate(ast)
          case ast.type
          when :nihil, :int, :float, :bool, :simple_str, :str then reify_primary(ast)
          when :if, :while, :negate, :not, :id, :assign, :binop then translate_basic(ast)
          when :gen_lit then translate_gen_lit(ast)
          when :call then translate_call(ast)
          when :seq then translate_sequence(ast)
          when :structured_str, :structured_gen_lit then translate_structured_str(ast)
          when :type_declaration then translate_type_declaration(ast)
          when :function_definition then translate_function_definition(ast)
          when :object_literal then translate_object_literal(ast)
          when :array_literal then translate_array_literal(ast)
          when :union_type then translate_union_type(ast)
          when :type_reference then translate_type_reference(ast)
          when :type_constant then translate_type_constant(ast)
          when :generic_type then translate_generic_type(ast)
          when :unit then translate_tuple(ast)
          when :tuple then translate_tuple(ast)
          when :type_annotation then translate_type_annotation(ast)
          else
            raise Error, "Unknown AST node type: \\#{ast.type}"
          end
        end

        def translate_tuple(node)
          [CONS[node.value&.map { |elem| translate(elem) }]]
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
          when :while then translate_while(node)
          when :negate then translate_negation(node)
          when :not then translate_not(node)
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
            Aua.logger.debug "Reifying string: #{node.inspect}"
            Str.new(node.value)
          else
            Aua.logger.warn "Unknown primary node type: #{node.type.inspect}"
            Nihil.new
          end
        end

        def translate_gen_lit(node)
          value = node.value
          [GEN[Str.new(value)]]
        end

        def translate_if(node)
          condition, true_branch, false_branch = node.value
          [
            Semantics.inst(:if, translate(condition), translate(true_branch), translate(false_branch))
          ]
        end

        def translate_while(node)
          condition, body = node.value
          condition_stmt = translate(condition)
          body_stmt = translate(body)
          Statement.new(type: :while, value: [condition_stmt, body_stmt])
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

        def translate_not(node)
          operand = node.value

          # For boolean NOT, we need to evaluate the operand and then negate it
          # This is different from arithmetic negation - it works on any expression that evaluates to a boolean
          operand_translation = translate(operand)

          [SEND[operand_translation, :not]]
        end

        def translate_assignment(node)
          name, value_node = node.value
          value = translate(value_node)
          [Semantics.inst(:let, name, value)]
        end

        def translate_binop(node)
          Aua.logger.debug "Translating binop: #{node.inspect}"
          op, left_node, right_node = node.value # Special handling for assignment - different from other binops
          if op == :equals
            # Handle different types of assignment
            case left_node.type
            when :id
              # Simple variable assignment: x = value
              name = left_node.value
              value = translate(right_node)
              return [Semantics.inst(:let, name, value)]
            when :binop
              # Check if it's member access assignment: obj.field = value
              raise Error, "Unsupported assignment target: #{left_node.inspect}" unless left_node.value[0] == :dot

              # Member assignment: obj.field = value
              obj_node = left_node.value[1]
              field_node = left_node.value[2]

              # Object should be an ID for now (could be extended later)
              unless obj_node.type == :id
                raise Error, "Member assignment currently only supports variable objects, got #{obj_node.inspect}"
              end

              # Field should be an ID
              raise Error, "Field name must be an identifier, got #{field_node.inspect}" unless field_node.type == :id

              obj_name = obj_node.value
              field_name = field_node.value
              value = translate(right_node)

              # Create a member assignment statement
              return [Statement.new(type: :member_assignment, value: [obj_name, field_name, value])]

            else
              raise Error, "Left side of assignment must be a variable or member access, got #{left_node.inspect}"
            end
          end

          # Special handling for member access - don't translate the right side
          if op == :dot
            left = translate(left_node)
            # Right side should be an ID node representing the field name
            if right_node.type == :id
              field_name = right_node.value
              return Binop.binary_operation(op, left, field_name)
            elsif right_node.type == :call
              meth, args = right_node.value
              args.map! { |arg| translate(arg) }
              return SEND[left, meth.to_sym, *args]
            end

            raise Error,
                  "Right side of member access must be a field name, got #{right_node.inspect} (#{right_node.type})"
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
              when :eq then binop_equals(left, right)
              when :neq then binop_not_equals(left, right)
              when :gt then [SEND[left, :gt, right]]
              when :lt then [SEND[left, :lt, right]]
              when :gte then [SEND[left, :gte, right]]
              when :lte then [SEND[left, :lte, right]]
              when :dot then [Statement.new(type: :member_access, value: [left, right])]
              when :and then [SEND[left, :and, right]]
              when :or then [SEND[left, :or, right]]
              when :as then handle_type_cast(left, right)
              when :colon then handle_type_annotation(left, right)
              when :tilde then handle_enum_selection(left, right)
              when :lambda then handle_lambda(left, right)
              else
                raise Error, "Unknown binary operator: #{operator}"
              end
            end

            private

            def handle_lambda(left, right)
              Aua.logger.info "Handling lambda: #{left.inspect} => #{right.inspect}"

              # Handle different parameter patterns
              args = case left
                     when ->(node) { node.respond_to?(:type) && node.type == :unit }
                       # Empty parameter list: () => expr
                       []
                     when ->(node) { node.respond_to?(:type) && node.type == :id }
                       # Single parameter: x => expr
                       [left]
                     when ->(node) { node.respond_to?(:type) && node.type == :tuple }
                       # Multiple parameters: (x, y, z) => expr
                       left.value
                     else
                       # Default case
                       left
                     end

              body = right

              # lhs is the arg list, rhs is the body
              LAMBDA[args, body]
            end

            def handle_type_cast(left, right)
              Aua.logger.info("Binop#handle_type_cast") do
                "Type casting: #{left.inspect} as #{right.inspect}"
              end

              # Unwrap rhs until we get a single value
              right = right.first while right.is_a?(Array) && right.size == 1

              # Aua.logger.info("binary_operation") { "Aua vm env => #{Aua.vm.instance_variable_get(:@env).inspect}" }

              klass = resolve_cast_target(right)
              Aua.logger.info("Binop#handle_type_cast") { "Resolved cast target: #{klass.inspect}" }
              CAST[left, klass]
            end

            def handle_type_annotation(left, right)
              Aua.logger.info "Type annotation: #{left.inspect} : #{right.inspect}"

              # Type annotations for now just return the left side value
              # In the future, this could be enhanced for type checking
              # For now, we'll just return the left value and ignore the type annotation
              left
            end

            def resolve_cast_target(right)
              if right.is_a?(Klass)
                right
              elsif right.is_a?(Statement) && right.type == :id
                # Defer type lookup to execution time by creating a special statement
                Statement.new(type: :type_lookup, value: right.value.first)
              elsif right.is_a?(IR::Types::TypeReference)
                # Type reference from parse_type_expression - defer lookup to execution time
                Statement.new(type: :type_lookup, value: right.name)
              elsif right.is_a?(IR::Types::GenericType)

                #   # Handle generic types like List<String>
                # debugger
                Statement.new(type: :generic_type_lookup, value: { base: right.base_type, args: right.type_params })
                #   # For now, we'll defer to runtime to handle the generic type casting
                #   Statement.new(type: :generic_type_cast, value: right)
                # right
              else
                Aua::Str.klass
              end
            end

            def handle_enum_selection(left, right)
              Aua.logger.info "Enum selection: #{left.inspect} ~ #{right.inspect}"

              # The ~ operator is like 'as' but specifically for union types
              # It converts the union type into a dynamic class for casting

              # Unwrap rhs until we get a single value
              right = right.first while right.is_a?(Array) && right.size == 1

              if right.is_a?(IR::Types::UnionType)
                # Inline union type - create dynamic class immediately
                choices = extract_choices_from_union_type(right)
                union_class = Statement.new(type: :dynamic_union_class, value: choices)
              elsif right.is_a?(IR::Types::TypeReference)
                # Type reference - defer lookup to runtime
                union_class = Statement.new(type: :union_type_lookup, value: right.name)
              else
                # Fallback - try to treat as regular type
                union_class = resolve_cast_target(right)
              end

              CAST[left, union_class]
            end

            def extract_choices_from_union_type(union_type)
              union_type.types.map do |type_obj|
                if type_obj.is_a?(IR::Types::TypeConstant)
                  # Extract the actual value from the AST node
                  ast_node = type_obj.name
                  if ast_node.respond_to?(:value)
                    ast_node.value
                  else
                    ast_node.inspect # Fallback
                  end
                else
                  type_obj.inspect # Fallback
                end
              end
            end

            def extract_union_choices(right)
              # Handle different forms of union types
              right = right.first if right.is_a?(Array) && right.size == 1

              if right.is_a?(Statement)
                case right.type
                when :union_choices
                  # Already processed union type choices
                  right.value
                when :type_reference
                  # Type reference: resolve the type
                  type_name = right.value
                  type_def = Aua.vm.instance_variable_get(:@env)[type_name]
                  if type_def.respond_to?(:choices)
                    type_def.choices
                  else
                    [type_name] # Fallback if type not found
                  end
                when :id
                  # Legacy ID case
                  type_name = right.value.first
                  type_def = Aua.vm.instance_variable_get(:@env)[type_name]
                  if type_def.respond_to?(:choices)
                    type_def.choices
                  else
                    [type_name] # Fallback if type not found
                  end
                else
                  [right]
                end
              else
                [right]
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

            def binop_equals(left, right)
              # unwrap left and right until we get a single value
              left = left.first while left.is_a?(Array) && left.size == 1
              right = right.first while right.is_a?(Array) && right.size == 1
              [SEND[left, :eq, right]]
            end

            def binop_not_equals(left, right)
              # unwrap left and right until we get a single value
              left = left.first while left.is_a?(Array) && left.size == 1
              right = right.first while right.is_a?(Array) && right.size == 1
              # Use SEND to call .eq and then negate the result with .not
              eq_result = SEND[left, :eq, right]
              [SEND[eq_result, :not]]
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

        # Translation methods for union types
        def translate_union_type(ast)
          # Union type is represented as an array of its constituent types
          types = ast.value.map { |child| translate(child).first }
          [IR::Types::UnionType.new(types)]
        end

        def translate_type_reference(ast)
          # Type reference to an existing type
          type_name = ast.value
          [IR::Types::TypeReference.new(type_name)]
        end

        def translate_type_constant(ast)
          # Type constant (like String, Int, etc.)
          type_name = ast.value
          [IR::Types::TypeConstant.new(type_name)]
        end

        def translate_function_definition(node)
          # Function definition: fun name(params) body end
          function_name, parameters, body = node.value

          # Translate the body to VM statements
          translated_body = translate(body)

          # Create a function object that stores the parameters and translated body
          function_obj = Statement.new(
            type: :function_definition,
            value: {
              name: function_name,
              parameters: parameters,
              body: translated_body
            }
          )

          # Store the function in the environment using assignment semantics
          [Semantics.inst(:let, function_name, function_obj)]
        end

        # Translation methods for generic types
        def translate_generic_type(ast)
          # Generic type like List<String> - represented as a generic type with base type and type parameters
          base_type, type_params = ast.value
          translated_params = type_params.flat_map { |param| translate(param).first }
          [IR::Types::GenericType.new(base_type, translated_params)]
        end

        def translate_type_annotation(ast)
          # Type annotations: expr : Type
          # We need to preserve the type information for the left side
          left, right = ast.value
          left_stmt = translate(left)
          right_stmt = translate(right)

          # Create a special statement that carries both the value and type info
          Statement.new(type: :typed_value, value: [left_stmt, right_stmt])
        end
      end
    end
  end
end
