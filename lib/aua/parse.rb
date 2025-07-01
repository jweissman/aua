require "aua/ast"
require "aua/grammar"

# Aua is a programming language and interpreter written in Ruby...
module Aua
  # A parser for the Aua language that builds an abstract syntax tree (AST).
  # Consumes tokens and produces an AST.
  class Parse
    module Enumerators
      class StructuredString
        include Aua::Grammar

        attr_reader :parser

        def initialize(parser)
          @parser = parser
        end

        def str_part(yielder)
          yielder << s(:str, parser.current_token.value)
          parser.advance
          true
        end

        def interpolation_start(yielder)
          parser.advance
          yielder << parser.send(:parse_expression)
          unless parser.current_token.type == :interpolation_end
            raise Error, "Expected interpolation_end, got #{parser.current_token.type}"
          end

          parser.advance
          true
        end

        def gen_end(_yielder)
          parser.current_string_quote = "\"\"\""
          parser.advance
          false
        end
        alias gen_lit gen_end

        def str_end(_yielder)
          parser.advance
          false
        end
        alias str_start str_end

        def method_missing(_method_name, *_args, **_kwargs, &)
          warn "Warning: Unhandled structured string token #{parser.current_token.type} at #{parser.current_token.at}"
          raise Error, "Unterminated string literal #{parser.current_token.at}" if parser.current_token.type == :eof

          raise Error,
                "Unexpected token in structured string: #{parser.current_token.type} #{parser.current_token.at}"
        end

        def respond_to_missing?(_method_name, _include_private = false)
          false
        end
      end

      def self.structured_string(parser)
        structured_string = StructuredString.new(parser)
        Enumerator.new do |yielder|
          loop while structured_string.send(parser.current_token.type, yielder)
        end
      end
    end

    attr_reader :current_token, :context
    attr_accessor :current_string_quote

    include Grammar

    def initialize(tokens, context = Runtime::Context.new(""))
      @tokens = tokens
      @buffer = [] # : Array[Syntax::Token | nil]
      @current_string_quote = nil
      @context = context

      advance
    end

    def tree
      ast = parse
      raise(Error, "Unexpected tokens after parsing: \\#{@current_token.inspect}") if unexpected_tokens?

      ast
    end

    def advance = @current_token = @buffer.shift || next_token

    def peek_token
      @buffer[0] = next_token if @buffer[0].nil?
    end

    def consume(expected_type, exact_value = nil)
      unless @current_token.type == expected_type
        raise Error, "Expected token type #{expected_type}, but got #{@current_token&.type || "EOF"}"
      end

      if exact_value && @current_token.value != exact_value
        raise Error, "Expected token value '#{exact_value}', but got '#{@current_token.value}'"
      end

      advance
    end

    def next_token
      @tokens.next
    rescue StopIteration
      Syntax::Token.new(type: :eof, value: nil, at: @current_token&.at || Aua::Text::Cursor.new(0, 0))
    end

    def unexpected_tokens? = @length != @current_token_index && @current_token.type != :eos

    def info(message) = Aua.logger.info("parse") { message }

    private

    def parse = parse_statements

    def statement_enumerator
      Enumerator.new do |yielder|
        loop do
          advance while @current_token.type == :eos
          # advance while @current_token.type == :str_end  # Commented out to allow empty strings
          break if %i[eos eof].include?(@current_token.type)

          statement = parse_expression
          raise Error, "Unexpected end of input while parsing statements" if statement.nil?

          yielder << statement
        end
      end
    end

    def parse_statements
      statements = statement_enumerator.to_a
      statements.size == 1 ? statements.first : s(:seq, statements.compact)
    end

    # Parses an expression
    def parse_expression
      Aua.logger.debug("parse-expr") { "Current token: #{@current_token.type} (#{@current_token.value})" }

      maybe_type_declaration = parse_type_declaration
      return maybe_type_declaration if maybe_type_declaration

      maybe_function_definition = parse_function_definition
      return maybe_function_definition if maybe_function_definition

      maybe_assignment = parse_assignment
      return maybe_assignment if maybe_assignment

      maybe_conditional = parse_conditional
      return maybe_conditional if maybe_conditional

      maybe_command = parse_command
      return maybe_command if maybe_command

      maybe_while = parse_while
      return maybe_while if maybe_while

      parse_binop
    end

    # Parses a type declaration: type TypeName = type_expression
    def parse_type_declaration
      return unless @current_token.type == :keyword && @current_token.value == "type"

      consume(:keyword, "type")
      parse_failure("type name") unless @current_token.type == :id
      type_name = @current_token.value
      consume(:id)
      consume(:equals)

      type_expr = parse_type_expression
      s(:type_declaration, type_name, type_expr)
    end

    # Parses a function definition: fun name(params) body end
    def parse_function_definition
      return unless @current_token.type == :keyword && @current_token.value == "fun"

      consume(:keyword, "fun")
      parse_failure("function name") unless @current_token.type == :id
      function_name = @current_token.value
      consume(:id)

      # Parse parameter list
      consume(:lparen)
      parameters = []
      unless @current_token.type == :rparen
        loop do
          parse_failure("parameter name") unless @current_token.type == :id
          parameters << @current_token.value
          consume(:id)
          break unless @current_token.type == :comma

          consume(:comma)
        end
      end
      consume(:rparen)

      # Parse function body (until 'end')
      body_statements = []

      # Skip any newlines after the parameter list
      advance while @current_token.type == :eos

      while @current_token.type != :keyword || @current_token.value != "end"
        break if @current_token.type == :eof

        # Skip newlines/whitespace within function body
        if @current_token.type == :eos
          advance
          next
        end

        statement = parse_expression
        body_statements << statement if statement

        # Skip newlines after each statement
        advance while @current_token.type == :eos
      end

      consume(:keyword, "end")

      body = body_statements.size == 1 ? body_statements.first : s(:seq, body_statements.compact)
      s(:function_definition, function_name, parameters, body)
    end

    def parse_type_expression
      base_type = case @current_token.type
                  when :simple_str
                    parse_string_literal_type
                  when :str_part
                    parse_quoted_string_literal_type
                  when :id
                    parse_type_reference
                  when :lbrace
                    parse_record_type
                  when :lparen
                    parse_parenthesized_type_expression
                  else
                    raise Error, "Expected type expression, got #{@current_token.type}"
                  end

      # Check for union (|) after parsing base type
      if @current_token.type == :pipe
        parse_union_type(base_type)
      else
        base_type
      end
    end

    # Parses record types: { field1: Type1, field2: Type2 }
    def parse_record_type
      consume(:lbrace)

      fields = [] # : Array[AST::Node]

      # Skip any whitespace/newlines after opening brace
      advance while @current_token.type == :eos

      # Handle empty record
      return parse_empty_record if @current_token.type == :rbrace

      # Parse fields
      loop do
        advance while @current_token.type == :eos
        field = parse_record_field
        fields << field
        advance while @current_token.type == :eos

        break unless continue_record_parsing?
      end

      consume(:rbrace)
      s(:record_type, fields)
    end

    # Parses union types: left_type | right_type | ...
    def parse_union_type(left_type)
      types = [left_type]

      while @current_token.type == :pipe
        consume(:pipe)
        types << parse_union_type_member
      end

      s(:union_type, types)
    end

    def parse_union_type_member
      case @current_token.type
      when :simple_str
        parse_union_string_constant
      when :str_part
        parse_union_string_part
      when :id
        parse_union_type_reference
      else
        parse_failure("type after '|'")
        raise Error, "Unreachable" # This won't be reached due to parse_failure raising
      end
    end

    def parse_union_string_constant
      value = @current_token.value
      consume(:simple_str)
      s(:type_constant, s(:simple_str, value))
    end

    def parse_union_string_part
      value = @current_token.value
      consume(:str_part)
      consume(:str_end) # Consume the closing quote
      s(:type_constant, s(:simple_str, value))
    end

    def parse_union_type_reference
      type_name = @current_token.value
      consume(:id)
      s(:type_reference, type_name)
    end

    def should_end_command_args?(token)
      %i[eos eof interpolation_end str_end].include?(token.type)
    end

    def command_argument_enumerator
      Enumerator.new do |yielder|
        while PRIMARY_NAMES.key?(@current_token.type)
          yielder << if @current_token.type == :str_part
                       parse_structured_str
                     else
                       Primitives.new(self).send("parse_#{PRIMARY_NAMES[@current_token.type]}")
                     end
          if @current_token.type == :comma
            consume(:comma)
          elsif should_end_command_args?(@current_token)
            break
            # TODO: Would be nice to test this somehow?
            # else
            #   raise Error, "Unexpected token in command arguments: #{@current_token.type} at #{@current_token.at}"
          end
        end
      end
    end

    # Parses a command or function call: id arg1 arg2 ...
    def parse_command
      return unless @current_token.type == :id

      id_token = @current_token
      save_token = @current_token
      save_buffer = @buffer.dup
      consume(:id)
      Aua.logger.debug " - Consumed command ID: #{id_token.value}"
      args = command_argument_enumerator.to_a
      Aua.logger.debug " - Parsed arguments: #{args.inspect}"
      if args.empty?
        @current_token = save_token
        @buffer = save_buffer
        return nil
      end
      Aua.logger.debug " - Call recognized with ID: #{id_token.value} and args: #{args.inspect}"
      s(:call, id_token.value, args)
    end

    def parse_assignment
      return unless @current_token.type == :id && peek_token&.type == :equals

      id = @current_token
      consume(:id)
      name = id.value
      consume(:equals)
      value = parse_expression
      s(:assign, name, value)
    end

    def parse_conditional
      return unless @current_token.type == :keyword && @current_token.value == "if"

      consume(:keyword, "if")
      condition = parse_expression
      true_branch, false_branch = parse_condition_body
      s(:if, condition, true_branch, false_branch)
    end

    def parse_condition_body
      # Check if this is a ternary-style conditional (with 'then')
      if @current_token.type == :keyword && @current_token.value == "then"
        consume(:keyword, "then")
        true_branch = parse_expression
        false_branch = s(:nihil) # Default to nihil for missing else branch
        if @current_token.type == :keyword && @current_token.value == "else"
          consume(:keyword, "else")
          false_branch = parse_expression
        end
      else
        # Block-style conditional
        # Expect statements until 'end' or 'else'
        true_statements = [] # : Array[untyped]

        # Skip optional newlines/eos after condition
        advance while @current_token.type == :eos

        # Parse statements until we hit 'elif', 'else' or 'end'
        while @current_token.type != :keyword || !%w[elif else end].include?(@current_token.value)
          stmt = parse_expression
          true_statements << stmt if stmt
          advance while @current_token.type == :eos # Skip statement separators
        end

        true_branch = true_statements.size == 1 ? true_statements.first : s(:seq, true_statements)
        false_branch = s(:nihil) # Default to nihil (no-op) for missing else branch

        # Handle optional 'elif' and 'else' blocks
        if @current_token.type == :keyword && @current_token.value == "elif"
          false_branch = parse_elif_chain
        elsif @current_token.type == :keyword && @current_token.value == "else"
          consume(:keyword, "else")
          advance while @current_token.type == :eos # Skip newlines after 'else'

          false_statements = [] # : Array[untyped]
          while @current_token.type != :keyword || @current_token.value != "end"
            stmt = parse_expression
            false_statements << stmt if stmt
            advance while @current_token.type == :eos
          end

          false_branch = false_statements.size == 1 ? false_statements.first : s(:seq, false_statements)
        end

        # Consume the 'end' keyword
        consume(:keyword, "end")

      end
      [true_branch, false_branch]
    end

    def parse_elif_chain
      # Parse 'elif' keyword
      consume(:keyword, "elif")

      # Parse the condition expression
      condition = parse_expression
      advance while @current_token.type == :eos # Skip newlines after condition

      # Parse statements in the elif block
      elif_statements = [] # : Array[untyped]
      while @current_token.type != :keyword || !%w[elif else end].include?(@current_token.value)
        stmt = parse_expression
        elif_statements << stmt if stmt
        advance while @current_token.type == :eos # Skip statement separators
      end

      true_branch = elif_statements.size == 1 ? elif_statements.first : s(:seq, elif_statements)
      false_branch = s(:nihil) # Default to nihil (no-op) for missing else branch

      # Handle additional 'elif' or 'else' blocks recursively
      if @current_token.type == :keyword && @current_token.value == "elif"
        false_branch = parse_elif_chain
      elsif @current_token.type == :keyword && @current_token.value == "else"
        consume(:keyword, "else")
        advance while @current_token.type == :eos # Skip newlines after 'else'

        else_statements = [] # : Array[untyped]
        while @current_token.type != :keyword || @current_token.value != "end"
          stmt = parse_expression
          else_statements << stmt if stmt
          advance while @current_token.type == :eos
        end

        false_branch = else_statements.size == 1 ? else_statements.first : s(:seq, else_statements)
      end

      # Return the conditional structure (don't consume 'end' here - let the parent do it)
      s(:if, condition, true_branch, false_branch)
    end

    def parse_binop(min_prec = 0)
      left = parse_unary
      raise Error, "Unexpected end of input while parsing binary operation" if left.nil?

      left = consume_binary_op(left) while binary_op?(@current_token.type) && precedent?(@current_token.type, min_prec)
      left
    end

    def parse_unary
      if @current_token.type == :minus
        consume(:minus)
        operand = parse_unary
        s(:negate, operand)
      elsif @current_token.type == :not
        consume(:not)
        operand = parse_unary
        s(:not, operand)
      else
        parse_primary
      end
    end

    def precedent?(operand, min_prec)
      return false unless BINARY_PRECEDENCE.key?(operand)

      BINARY_PRECEDENCE[operand] >= min_prec
    end

    def consume_binary_op(left)
      op_token = @current_token
      op = op_token.type
      prec = BINARY_PRECEDENCE[op]
      consume(op)

      # Special handling for tilde operator - parse the right side as a type expression
      if op == :tilde
        right = parse_type_expression
      else
        next_min_prec = Set[:pow].include?(op) ? prec : prec + 1
        right = parse_binop(next_min_prec)
      end

      s(:binop, op, left, right)
    end

    def binary_op?(type) = BINARY_PRECEDENCE.key?(type)

    def parse_primary
      raise Aua::Error, "Unexpected end of input while parsing primary expression" if @current_token.type == :eos
      return parse_structured_str if %i[str_part interpolation_start].include?(@current_token.type)

      if @current_token.type == :prompt
        advance
        return parse_primary
      end

      return primitives.send "parse_#{PRIMARY_NAMES[@current_token.type]}" if PRIMARY_NAMES.key?(@current_token.type)

      parse_failure("Unexpected token type")
      # This should never be reached, but Steep needs a return value
      s(:error)
    end

    def primitives = @primitives ||= Primitives.new(self)
    def structured_string_enumerator = Enumerators.structured_string(self)

    # Parses a structured/interpolated string
    def parse_structured_str
      parts = structured_string_enumerator.to_a
      token_type = @current_string_quote == "\"\"\"" ? :structured_gen_lit : :structured_str
      # Reset the string quote after determining the type
      @current_string_quote = nil
      return s(:str, parts.first.value) if parts.size == 1 && parts.first.type == :str

      s(token_type, parts)
    end

    def parse_string_literal_type
      # String literal type like 'yes' -> type_constant containing simple_str
      value = @current_token.value
      consume(:simple_str)
      s(:type_constant, s(:simple_str, value))
    end

    def parse_quoted_string_literal_type
      # Double-quoted string literal type like "active"
      value = @current_token.value
      consume(:str_part)
      consume(:str_end) # Consume the closing quote
      s(:type_constant, s(:simple_str, value))
    end

    def parse_type_reference
      # Reference to another type
      type_name = @current_token.value
      consume(:id)
      s(:type_reference, type_name)
    end

    def parse_empty_record
      consume(:rbrace)
      s(:record_type, [])
    end

    def parse_record_field
      # raise Error, "Expected field name, got #{@current_token.type}" unless @current_token.type == :id
      parse_failure("field name") unless @current_token.type == :id

      field_name = @current_token.value
      consume(:id)
      consume(:colon)

      # Skip any whitespace/newlines after colon
      advance while @current_token.type == :eos

      # Parse field type
      field_type = parse_type_expression
      s(:field, field_name, field_type)
    end

    def continue_record_parsing?
      case @current_token.type
      when :comma
        consume(:comma)
        # Skip any whitespace/newlines after comma
        advance while @current_token.type == :eos
        return true
      when :rbrace
        return false
      else
        # raise Error, "Expected ',' or '}' in record type, got #{@current_token.type}"
        parse_failure("',' or '}' in record type")
      end

      false
    end

    def parse_failure(expectation, at: @current_token.at)
      cursor = at # : Aua::Text::Cursor
      # {expectation}, got #{@current_token.type}:

      # {Text.indicate(@context.source_document.send(:text), cursor)}
      raise Error,
            "Expected #{expectation}, got #{@current_token.type} #{@current_token.at}:\n#{Text.indicate(
              @context.source_document.send(:text),
              cursor
            ).join("\n")}\n"
    end

    def parse_while
      return nil unless @current_token.type == :keyword && @current_token.value == "while"

      consume(:keyword, "while")
      condition = parse_expression
      advance while @current_token.type == :eos # Skip newlines

      # Parse the body statements
      body_statements = [] # : Array[untyped]
      while @current_token.type != :keyword || @current_token.value != "end"
        stmt = parse_expression
        body_statements << stmt if stmt
        advance while @current_token.type == :eos # Skip statement separators
      end

      # Consume the 'end' keyword
      consume(:keyword, "end")

      body = body_statements.size == 1 ? body_statements.first : s(:seq, body_statements)
      s(:while, condition, body)
    end

    def parse_parenthesized_type_expression
      consume(:lparen)
      type_expr = parse_type_expression
      consume(:rparen)
      type_expr
    end
  end
end
