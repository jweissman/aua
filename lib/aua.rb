# frozen_string_literal: true

require "aua/version"

# The main Aua interpreter module.
#
# Aua is a programming language and interpreter written in Ruby.
# This module serves as the entry point for using the Aua interpreter,
# providing functionality for lexing, parsing, and executing Aua code.
#
# @example
#   Aua.run("let x = 42")
module Aua
  class Error < StandardError; end

  Token = Data.define(:type, :value)

  # Provides utility methods for syntax-related tasks.
  module Syntax
    # Creates a new token with the given type and optional value.
    def t(type, value = nil) = Token.new(type:, value:)
  end

  # Provides utility methods for text processing, such as indicating a position in code.
  module Text
    # Represents a cursor in the source code, tracking the current column and line.
    class Cursor
      attr_reader :column, :line

      def initialize(col, line)
        @column = col
        @line = line
      end

      def advance = @column += 1
      def newline = @line += 1
    end

    # Represents a document containing source code, with methods to navigate and manipulate it.
    class Document
      attr_reader :cursor, :position

      def initialize(text)
        @text = text
        @cursor = Cursor.new(1, 1)
        @position = 0
      end

      def peek = @text.chars.fetch(@position, nil)
      def finished? = @position >= @text.length
      def slice(start, length) = @text.slice(start, length)

      # Advances the lexer by one character, updating position and line/column counters.
      def advance
        @position += 1
        @cursor.advance
        return unless peek == "\n"

        @cursor.newline
      end

      def indicate = Text.indicate(@text, @cursor)
    end

    # Indicates the position of a character in the code by printing the line
    # and an indicator pointing to the character's position.
    #
    # @param code [String] The code to indicate within.
    # @param column [Integer] The column number to point to (1-based).
    # @param line [Integer, nil] The line number to point to (1-based), or nil for all lines.
    # @return [Array<String>] The lines with an indicator.
    def self.indicate(text, cursor)
      lines = text.lines
      line = cursor.line
      column = cursor.column
      lines.each_with_index.map do |line_content, index|
        if line.nil? || index + 1 == line
          "#{line_content.chomp}\n#{" " * (column - 1)}^"
        else
          line_content.chomp
        end
      end
    end
  end

  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    include Syntax

    # @param code [String] The source code to lex.
    # @raise [Error] If an unexpected character is encountered.
    #
    # @example
    #   lexer = Aua::Lex.new("let x = 42")
    #   tokens = lexer.tokens
    #
    # @see Aua::Interpreter for the main entry point
    # @see Aua::Parse for parsing functionality
    # @see Aua::VM for virtual machine execution
    def initialize(code)
      @doc = Text::Document.new(code)
      @tokens = []
    end

    def current_line   = @doc.cursor.line
    def current_column = @doc.cursor.column
    def current_char   = @doc.peek

    # Returns the array of tokens generated from the source code.
    def tokens
      lex
      @tokens
    end

    # Lexes an identifier or boolean literal.
    def identifier
      start_pos = @doc.position #  - 1
      advance while current_char&.match?(/[a-zA-Z_]/)
      value = @doc.slice(start_pos, @doc.position - start_pos)
      case value
      when "true" then t(:bool, true)
      when "false" then t(:bool, false)
      when "nihil" then t(:nihil, true)
      else
        t(:id, value)
      end
    end

    # Lexes an integer or floating-point literal.
    def number_lit
      start_pos = @doc.position
      has_dot = false
      while current_char&.match?(/\d|\./)
        has_dot = true if current_char == "."
        advance
      end
      number_str = @doc.slice(start_pos, @doc.position - start_pos)
      number_token_from_string(number_str, has_dot)
    end

    def number_token_from_string(str, has_dot)
      has_dot ? t(:float, str.to_f) : t(:number, str.to_i)
    end

    # Lexes a string literal, accumulating characters between quotes.
    def string
      advance # skip opening quote
      chars = [] # : Array[String]
      while current_char && current_char != '"'
        chars << current_char
        advance
      end
      advance # skip closing quote
      t(:str, chars.join)
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def recognize
      case current_char
      when /\s/ then handle_whitespace
      when /\d/ then handle_number
      when /[a-zA-Z_]/ then handle_identifier
      when '"' then handle_string
      when "-" then handle_minus
      when "(" then handle_lparen
      when ")" then handle_rparen
      else handle_unexpected
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def advance = @doc.advance

    # Main lexing loop: emits tokens for the input code.
    def lex
      recognize until eof?
      @tokens
    end

    def eof?
      @doc.peek.nil? || @doc.finished?
    end

    def unexpected_character_message
      <<~ERROR
        Unexpected character '#{current_char.inspect}' at line #{current_line}, column #{current_column}

        #{@doc.indicate}

        Please check your code for syntax errors.
      ERROR
    end

    private

    def handle_whitespace = advance
    def handle_identifier = @tokens << identifier
    def handle_string = @tokens << string

    def handle_minus
      advance
      @tokens << t(:minus)
    end

    def handle_lparen
      advance
      @tokens << t(:lparen)
    end

    def handle_rparen
      advance
      @tokens << t(:rparen)
    end

    def handle_number = @tokens << number_lit
    def handle_unexpected = raise(Error, unexpected_character_message)
  end

  # The AST (Abstract Syntax Tree) node definitions for Aua.
  module AST
    Node = Data.define(:type, :value)
  end

  # Grammar helpers for constructing AST nodes.
  module Grammar
    def s(type, *values)
      normalized_values = if values.empty?
                            nil
                          else
                            values.length == 1 ? values.first : values
                          end
      AST::Node.new(type:, value: normalized_values)
    end

    # A class for parsing primitive values in Aua.
    class Primitives
      include Grammar

      def initialize(parse)
        @parse = parse
      end

      def parse_id
        identifier = @parse.current_token.value
        @parse.consume(:id)
        s(:id, identifier)
      end

      def parse_number
        number = @parse.current_token.value
        @parse.consume(:number)
        s(:int, number)
      end

      def parse_float
        float = @parse.current_token.value
        @parse.consume(:float)
        s(:float, float)
      end

      def parse_bool
        bool = @parse.current_token.value
        @parse.consume(:bool)
        s(:bool, bool)
      end

      def parse_str
        str = @parse.current_token.value
        @parse.consume(:str)
        s(:str, str)
      end

      def parse_nihil
        @parse.consume(:nihil)
        s(:nihil, nil)
      end

      def parse_parens
        @parse.consume(:lparen)
        expr = @parse.parse_expression
        @parse.consume(:rparen)
        expr
      end

      # Parses a unary minus expression.
      def parse_negation
        @parse.consume(:minus)
        raise Error, "Unexpected end of input after unary minus" if @parse.current_token.type == :eos

        unless %i[number float bool str id minus].include?(@parse.current_token.type)
          raise Error, "Unary minus must be followed by a literal or identifier, got #{@current_token.type}"
        end

        operand = @parse.parse_primary
        s(:negate, operand)
      end
    end
  end

  extend Grammar
  NOTHING = s(:nihil)

  # A parser for the Aua language that builds an abstract syntax tree (AST).
  # Consumes tokens and produces an AST.
  class Parse
    attr_reader :current_token

    include Grammar
    include Syntax

    def initialize(tokens)
      @tokens = tokens
      @current_token_index = 0
      @current_token = @tokens[@current_token_index]
      @length = @tokens.length
    end

    def consume(expected_type)
      unless @current_token.type == expected_type
        raise Error, "Expected token type #{expected_type}, but got #{@current_token&.type || "EOF"}"
      end

      next_token

      # @current_token = next_token
    end

    def next_token
      # Advances to the next token in the token stream.
      @current_token_index += 1
      @current_token = if @current_token_index < @length
                         @tokens[@current_token_index]
                       else
                         Token.new(type: :eos, value: nil)
                       end
      @current_token
    rescue IndexError
      @current_token = Token.new(type: :eos, value: nil)
      nil
    end

    def tree
      ast = begin
        parse
      rescue Error
        NOTHING
      end

      raise(Error, "Unexpected tokens after parsing: #{@current_token.inspect}") if unexpected_tokens?

      ast
    end

    def unexpected_tokens?
      @length != @current_token_index && @current_token.type != :eos
    end

    def parse = parse_expression
    def parse_expression = parse_primary

    PRIMARY_MAP = {
      lparen: :parse_parens,
      minus: :parse_negation,
      id: :parse_id,
      number: :parse_number,
      float: :parse_float,
      bool: :parse_bool,
      str: :parse_str,
      nihil: :parse_nihil
    }.freeze

    # Parses a primary expression (literal, identifier, or unary minus).
    def parse_primary
      primitives = Primitives.new(self)
      return primitives.send PRIMARY_MAP[@current_token.type] if PRIMARY_MAP.key?(@current_token.type)

      raise Error, "Unexpected token type: #{@current_token.type}"
    end

    def unexpected_token
      raise Error, "Unexpected token in primary expression: #{@current_token.type}"
    end

    def self.ast(...) = new(...).tree
  end

  # The base object for all Aua values.
  class Obj
    def klass = Klass.klass
  end

  # The class object for Aua types.
  class Klass < Obj
    def initialize(name, parent = nil)
      super()
      @name = name
      @parent = parent
    end

    def klass = send :itself
    def self.klass = Klass.new("Klass", klass)
    def self.obj = Klass.new("Obj", klass)
  end

  # The 'nothing' value in Aua.
  class Nihil < Obj
    def klass
      Klass.obj # : Klass
    end

    def name = "nothing"
    def value = nil
  end

  # Integer value in Aua.
  class Int < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Int", Klass.obj)
    def name = "int"
    attr_reader :value
  end

  # Floating-point value in Aua.
  class Float < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Float", Klass.obj)
    def name = "float"
    attr_reader :value
  end

  # Boolean value in Aua.
  class Bool < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Bool", Klass.obj)
    def name = "bool"
    attr_reader :value
  end

  # String value in Aua.
  class Str < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Str", Klass.obj)
    def name = "str"
    attr_reader :value
  end

  Statement = Data.define(:type, :value)

  # Semantic helpers for statements and let bindings.
  module Semantics
    MEMO = "_"
    def self.inst(type, *args)
      Statement.new(type:, value: args)
    end

    # LET = ->(name, value) { inst(:let, name, value) }
  end

  include Semantics
  RECALL = lambda do |item|
    # LET["_", item]
    Semantics.inst(:let, "_", item)
  end

  # The virtual machine for executing Aua ASTs.
  class VM
    extend Semantics

    def initialize(env = {})
      @env = env
    end

    def recall_primary(node)
      recollect = case node.type
                  when :int then Int.new(node.value)
                  when :float then Float.new(node.value)
                  when :bool then Bool.new(node.value)
                  when :str then Str.new(node.value)
                  else
                    puts "Unknown primary node type: #{node.type.inspect}"
                    Nihil.new
                  end
      [RECALL[recollect]]
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

    def translate(ast)
      case ast.type
      when :nihil then [RECALL[Nihil.new]]
      when :id then [RECALL[@env[ast.value] || Nihil.new]]
      when :int, :float, :bool, :str then recall_primary(ast)
      when :negate then translate_negation(ast)
      else
        raise Error, "Unknown AST node type: #{ast.type}"
      end
    end

    def evaluate(ast)
      ret = Nihil.new
      translate(ast).each do |stmt|
        ret = evaluate_one stmt
      end
      evaluate_one RECALL[ret]
      ret
    end

    def evaluate_one(stmt)
      # Evaluates a single statement in the VM.
      case stmt.type
      when :let
        name, value = stmt.value
        @env[name] = value
        value
      else
        raise Error, "Unknown statement type: #{stmt.type}"
      end
    rescue StandardError => e
      raise Error, "Evaluation error: #{e.message}"
    end
  end

  # The main interpreter class that combines lexing, parsing, and evaluation.
  #
  # @example
  # ```
  #   interpreter = Aua::Interpreter.new
  #   result = interpreter.run("some code")
  # ```
  #
  # @see Aua::Lex for lexing functionality
  # @see Aua::Parse for parsing functionality
  # @see Aua::Vm for virtual machine execution
  class Interpreter
    def initialize(env = {})
      @env = env
    end

    def lex(code) = Lex.new(code).send :tokens
    def parse(tokens) = Parse.ast tokens
    def vm = VM.new @env

    # Runs the Aua interpreter pipeline: lexing, parsing, and evaluation.
    # Something like the following:
    #
    #   code = "let x = 42"
    #   tokens = lex code
    #   ast = parse tokens
    #   vm.evaluate ast
    #
    # @param code [String] The source code to interpret.
    def run(code)
      pipeline = [method(:lex), method(:parse), vm.method(:evaluate)]
      pipeline.reduce(code) do |input, step|
        puts "#{step.name}: #{input.inspect}..."
        out = step.call(input)
        puts "#{step.name}: #{input.inspect} -> #{out.inspect}"
        out
      rescue Aua::Error => e
        puts "Error during processing: #{e.message}"
        # would be nice but we'd have to thread the position through the pipeline!
        raise e
      end
    end
  end

  # The main entry point for the Aua interpreter.
  #
  # @example
  #   Aua.run("some code")
  def self.run(code)
    interpreter = Interpreter.new
    interpreter.run(code)
  rescue Error => e
    puts "Aua interpreter error: #{e.message}"
    puts e.backtrace&.join("\n")
    # would be nice but we'd have to thread the position through the pipeline!
    raise e
  end
end
