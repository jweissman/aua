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

    attr_reader :current_token
    attr_accessor :current_string_quote

    include Grammar

    def initialize(tokens)
      @tokens = tokens
      @buffer = [] # : Array[Syntax::Token | nil]
      @current_string_quote = nil

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

    def info(message) = Aua.logger.info("aura:parse") { message }

    private

    def parse = parse_statements

    def statement_enumerator
      Enumerator.new do |yielder|
        loop do
          advance while @current_token.type == :eos
          advance while @current_token.type == :str_end
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
      info "parse-expr | Current token: #{@current_token.type} (#{@current_token.value})"

      maybe_type_declaration = parse_type_declaration
      return maybe_type_declaration if maybe_type_declaration

      maybe_assignment = parse_assignment
      return maybe_assignment if maybe_assignment

      maybe_conditional = parse_conditional
      return maybe_conditional if maybe_conditional

      maybe_command = parse_command
      return maybe_command if maybe_command

      parse_binop
    end

    # Parses a type declaration: type TypeName = type_expression
    def parse_type_declaration
      return unless @current_token.type == :keyword && @current_token.value == "type"

      consume(:keyword, "type")
      unless @current_token.type == :id
        raise Error, "Expected type name after 'type' keyword, got #{@current_token.type}"
      end

      type_name = @current_token.value
      consume(:id)
      consume(:equals)

      type_expr = parse_type_expression
      s(:type_declaration, type_name, type_expr)
    end

    def parse_type_expression
      case @current_token.type
      when :simple_str
        # String literal type like 'yes' -> type_constant containing simple_str
        value = @current_token.value
        consume(:simple_str)
        literal_type = s(:type_constant, s(:simple_str, value))

        # Check for union (|)
        if @current_token.type == :pipe
          parse_union_type(literal_type)
        else
          literal_type
        end
      when :str_part
        # Double-quoted string literal type like "active"
        value = @current_token.value
        consume(:str_part)
        consume(:str_end) # Consume the closing quote
        literal_type = s(:type_constant, s(:simple_str, value))

        # Check for union (|)
        if @current_token.type == :pipe
          parse_union_type(literal_type)
        else
          literal_type
        end
      when :id
        # Reference to another type
        type_name = @current_token.value
        consume(:id)
        ref_type = s(:type_reference, type_name)

        # Check for union (|)
        if @current_token.type == :pipe
          parse_union_type(ref_type)
        else
          ref_type
        end
      when :lbrace
        # Record type like { x: Int, y: Int }
        parse_record_type
      else
        raise Error, "Expected type expression, got #{@current_token.type}"
      end
    end

    # Parses record types: { field1: Type1, field2: Type2 }
    def parse_record_type
      consume(:lbrace)

      fields = [] # : Array[AST::Node]

      # Skip any whitespace/newlines after opening brace
      advance while @current_token.type == :eos

      # Handle empty record
      if @current_token.type == :rbrace
        consume(:rbrace)
        return s(:record_type, fields)
      end

      loop do
        # Skip any whitespace/newlines before field name
        advance while @current_token.type == :eos

        # Parse field name
        raise Error, "Expected field name, got #{@current_token.type}" unless @current_token.type == :id

        field_name = @current_token.value
        consume(:id)
        consume(:colon)

        # Skip any whitespace/newlines after colon
        advance while @current_token.type == :eos

        # Parse field type
        field_type = parse_type_expression
        fields << s(:field, field_name, field_type)

        # Skip any whitespace/newlines after field type
        advance while @current_token.type == :eos

        # Check for continuation
        if @current_token.type == :comma
          consume(:comma)
          # Skip any whitespace/newlines after comma
          advance while @current_token.type == :eos
        elsif @current_token.type == :rbrace
          break
        else
          raise Error, "Expected ',' or '}' in record type, got #{@current_token.type}"
        end
      end

      consume(:rbrace)
      s(:record_type, fields)
    end

    # Parses union types: left_type | right_type | ...
    def parse_union_type(left_type)
      types = [left_type]

      while @current_token.type == :pipe
        consume(:pipe)
        case @current_token.type
        when :simple_str
          value = @current_token.value
          consume(:simple_str)
          types << s(:type_constant, s(:simple_str, value))
        when :str_part
          value = @current_token.value
          consume(:str_part)
          consume(:str_end) # Consume the closing quote
          types << s(:type_constant, s(:simple_str, value))
        when :id
          type_name = @current_token.value
          consume(:id)
          types << s(:type_reference, type_name)
        else
          raise Error, "Expected type after '|', got #{@current_token.type}"
        end
      end

      s(:union_type, types)
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
      info " - Consumed command ID: #{id_token.value}"
      args = command_argument_enumerator.to_a
      info " - Parsed arguments: #{args.inspect}"
      if args.empty?
        @current_token = save_token
        @buffer = save_buffer
        return nil
      end
      info " - Call recognized with ID: #{id_token.value} and args: #{args.inspect}"
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
      consume(:keyword, "then")
      true_branch = parse_expression
      false_branch = nil
      if @current_token.type == :keyword && @current_token.value == "else"
        consume(:keyword, "else")
        false_branch = parse_expression
      end
      [true_branch, false_branch]
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
      next_min_prec = Set[:pow].include?(op) ? prec : prec + 1
      right = parse_binop(next_min_prec)
      s(:binop, op, left, right)
    end

    def binary_op?(type) = BINARY_PRECEDENCE.key?(type)

    def parse_primary
      raise Aua::Error, "Unexpected end of input while parsing primary expression" if @current_token.type == :eos
      return parse_structured_str if @current_token.type == :str_part

      if @current_token.type == :prompt
        advance
        return parse_primary
      end

      return primitives.send "parse_#{PRIMARY_NAMES[@current_token.type]}" if PRIMARY_NAMES.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    def primitives = @primitives ||= Primitives.new(self)
    def structured_string_enumerator = Enumerators.structured_string(self)

    # Parses a structured/interpolated string
    def parse_structured_str
      parts = structured_string_enumerator.to_a
      token_type = @current_string_quote == "\"\"\"" ? :structured_gen_lit : :structured_str
      return s(:str, parts.first.value) if parts.size == 1 && parts.first.type == :str

      s(token_type, parts)
    end
  end
end
