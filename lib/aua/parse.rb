require "aua/ast"
require "aua/grammar"

# Aua is a programming language and interpreter written in Ruby...
module Aua
  # A parser for the Aua language that builds an abstract syntax tree (AST).
  # Consumes tokens and produces an AST.
  class Parse
    attr_reader :current_token

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
      Syntax::Token.new(
        type: :eof, value: nil, at: @current_token&.at || Aua::Text::Cursor.new(0, 0)
      )
    end

    def unexpected_tokens?
      @length != @current_token_index && @current_token.type != :eos
    end

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
      # statements = [] # : Array[AST::Node]
      # while @current_token.type != :eos && @current_token.type != :eof
      #   advance while @current_token.type == :eos
      #   advance while @current_token.type == :str_end
      #   break if %i[eos eof].include?(@current_token.type)

      #   statement = parse_expression
      #   raise Error, "Unexpected end of input while parsing statements" if statement.nil?

      #   statements << statement
      #   advance while @current_token.type == :eos
      #   advance while @current_token.type == :str_end
      # end

      statements.size == 1 ? statements.first : s(:seq, statements.compact)
    end

    # Parses an expression
    def parse_expression
      info "parse-expr | Current token: #{@current_token.type} (#{@current_token.value})"
      maybe_assignment = parse_assignment
      return maybe_assignment if maybe_assignment

      maybe_conditional = parse_conditional
      return maybe_conditional if maybe_conditional

      maybe_command = parse_command
      return maybe_command if maybe_command

      parse_binop
    end

    # Parses a command or function call: id arg1 arg2 ...
    def parse_command
      return unless @current_token.type == :id

      id_token = @current_token
      info "Parsing command with ID: #{id_token.value}"
      args = [] # : Array[AST::Node]
      save_token = @current_token
      save_buffer = @buffer.dup
      consume(:id)
      info " - Consumed command ID: #{id_token.value}"

      # Accept one or more primary expressions as arguments (space-separated)
      while PRIMARY_NAMES.key?(@current_token.type)
        # Special case: if the token is :str_part, parse the whole structured string
        arg = if @current_token.type == :str_part
                parse_structured_str
              else
                Primitives.new(self).send("parse_#{PRIMARY_NAMES[@current_token.type]}")
              end
        args << arg
        info " - Parsed argument: #{arg.inspect}"
        if @current_token.type == :comma
          consume(:comma)
          # info " - Consumed comma, expecting more args"
        elsif %i[eos eof interpolation_end str_end].include?(@current_token.type)
          # info " - End of arguments reached"
          break
        else
          # If the next token is a valid statement starter, break out of the argument loop
          # break if %i[id keyword eof eos].include?(@current_token.type)

          raise Error, "Unexpected token while parsing arguments: \\#{@current_token.type}"
        end
      end

      args.compact!

      info " - Parsed arguments: #{args.inspect}"
      if args.empty?
        # Not a call, restore state and return nil
        @current_token = save_token
        @buffer = save_buffer
        # info " - No arguments found, restoring state and returning nil.."
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

      # Aua.logger.info("parse:pri") { "expression with token: #{@current_token.type} (#{@current_token.value})" }

      # Handle structured/interpolated strings
      return parse_structured_str if @current_token.type == :str_part

      # Detect triple-quoted string start
      if @current_token.type == :prompt
        advance
        return parse_primary
      end

      # primitives = Primitives.new(self)
      return primitives.send "parse_#{PRIMARY_NAMES[@current_token.type]}" if PRIMARY_NAMES.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    def primitives = @primitives ||= Primitives.new(self)

    # (update_token_type)
    def structured_string_enumerator
      Enumerator.new do |yielder|
        loop do
          case @current_token.type
          when :str_part
            yielder << s(:str, @current_token.value)
            advance
          when :interpolation_start
            advance
            yielder << parse_expression
            unless @current_token.type == :interpolation_end
              raise Error, "Expected interpolation_end, got #{@current_token.type}"
            end

            advance
          when :gen_end, :gen_lit
            @current_string_quote = "\"\"\""

            advance
            break
          when :str_end
            advance
            break
          else
            raise Error, "Unterminated string literal #{current_token.at}" if current_token.type == :eof

            raise Error, "Unexpected token in structured string: #{current_token.type} #{current_token.at}"
          end
        end
      end
    end

    # Parses a structured/interpolated string
    # @type method parse_structured_str: (bool) -> AST::Node
    # (triple_quoted = @current_string_quote == '"""')
    def parse_structured_str
      parts = structured_string_enumerator.to_a # (->(type) { token_type = type }).to_a
      token_type = @current_string_quote == "\"\"\"" ? :structured_gen_lit : :structured_str
      return s(:str, parts.first.value) if parts.size == 1 && parts.first.type == :str

      s(token_type, parts)
    end
  end
end
