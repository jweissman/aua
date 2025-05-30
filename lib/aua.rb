# frozen_string_literal: true

require_relative "aua/version"

module Aua
  class Error < StandardError; end

  Result = Data.define(:value, :error, :message) do
    def success?
      error.nil?
    end

    class << self
      def ok(val) = new(value: val, error: nil, message: nil)

      def err(err, message: nil)
        new(value: nil, error: err, message: message)
      end
    end
  end

  Token = Data.define(:type, :value)

  module Syntax
    def t(type, value = nil) = Token.new(type:, value:)
  end

  extend Syntax
  EOS = t(:eos)

  # Provides utility methods for text processing.
  module Text
    def self.indicate(code, position)
      lines = code.lines
      line_number = lines.index { |line| line.include?(code[position]) } + 1
      line_content = lines[line_number - 1]
      indicator = " " * (position - lines[0...line_number - 1].join.length) + "^"
      "#{line_content.strip}\n#{indicator} (line #{line_number})"
    end
  end

  # A lexer for the Aua language.
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
      @code = code
      @position = -1
      @length = code.length
      @tokens = []
      @current_token = nil
      @current_char = nil
      @current_line = 1
      @current_column = 0

      advance
    end

    def advance
      if @position < @length
        @current_char = @code[@position]
        @position += 1
        @current_column += 1
        if @current_char == "\n"
          @current_line += 1
          @current_column = 0
        end
      else
        @current_char = nil
      end
    end

    def tokens
      lex
      @tokens.each do |token|
        print "Token: #{token.type} - #{token.value.inspect}" if token.type != :eos
      end
      @tokens
    end

    def identifier
      start_pos = @position
      advance while @current_char&.match?(/[a-zA-Z_]/)
      t(:id, @code[start_pos...@position])
    end

    def number
      start_pos = @position
      advance while @current_char&.match?(/\d/)
      number_str = @code[start_pos...@position]
      t(:number, number_str.to_i)
    end

    def lex
      accept until eof?
    end

    def eof?
      @position >= @length && @current_char.nil?
    end

    def accept
      case @current_char
      when /\s/
        advance
      when /[a-zA-Z]/
        @tokens << identifier
      when /\d/
        @tokens << number
      else
        raise Error, unexpected_character_message
      end
    end

    def unexpected_character_message
      <<~ERROR
        Unexpected character '#{@current_char.inspect}' at line #{@current_line}, column #{@current_column}

        #{Text.indicate(@code, @position)}

        Please check your code for syntax errors.
      ERROR
    end
  end

  module AST
    Node = Data.define(:type, :value)
  end

  module Grammar
    def s(type, *values)
      normalized_values = if values.empty?
                            nil
                          else
                            values.length == 1 ? values.first : values
                          end
      AST::Node.new(type, normalized_values)
    end
  end

  extend Grammar
  NOTHING = s(:nihil)

  # A parser for the Aua language that builds an abstract syntax tree (AST).
  class Parse
    include Grammar

    def initialize(tokens)
      @tokens = tokens
      @current_token_index = 0
      @current_token = @tokens[@current_token_index]
      @length = @tokens.length

      puts "Parsing tokens: #{@tokens.inspect}"
    end

    def consume(expected_type)
      unless @current_token.type == expected_type
        raise Error, "Expected token type #{expected_type}, but got #{@current_token&.type || "EOF"}"
      end

      @current_token = next_token
    end

    def next_token
      @current_token_index += 1
      if @current_token_index < @length
        @tokens[@current_token_index]
      else
        @current_token = EOS
      end
      @current_token
    rescue IndexError
      @current_token = EOS
      nil
    end

    def tree
      ast = begin
        parse
      rescue Error => e
        puts "Parsing error: #{e.message}"
        puts Text.indicate(@tokens.map(&:value).join, e.message.index(e.message.split.last))
        NOTHING
      end

      unless @length == @current_token_index
        raise Error, "Unexpected tokens after parsing: #{@tokens[@current_token_index..].map(&:value).join(", ")}"
      end

      ast
    end

    def parse = parse_expression
    def parse_expression = parse_primary

    def parse_primary
      if @current_token.type == :id
        identifier = @current_token.value
        consume(:id)
        s(:id, identifier)
      elsif @current_token.type == :number
        number = @current_token.value
        consume(:number)
        s(:int, number)
      end
    end

    def self.ast(...) = new(...).tree
  end

  class Obj
    def klass = Klass.klass
  end

  class Klass < Obj
    def initialize(name)
      @name = name
    end

    def klass = self
    def self.klass = Klass.new("Klass")
  end

  class Nihil < Obj
    def klass = Klass.new("Nihil")
    def name = "nothing"
  end

  Statement = Data.define(:type, :value)

  module Semantics
    def self.inst(type, *args)
      Statement.new(type: type, value: args)
    end

    LET = ->(name, value) { inst(:let, name, value) }
  end

  include Semantics
  RECALL = -> { LET["_", it] }

  # A virtual machine for executing the Aua language.
  #
  # @example
  #   vm = Aua::VM.new
  #   result = vm.evaluate(ast)
  #
  # @see Aua::Interpreter for the main entry point
  # @see Aua::Lex for lexing functionality
  # @see Aua::Parse for parsing functionality
  class VM
    extend Semantics

    def initialize(env = {})
      @env = env
    end

    def lower(ast)
      case ast.type
      when :id then [RECALL[@env[ast.value] || Nihil.new]]
      when :int then [RECALL[ast.value]]
      else
        raise Error, "Unknown AST node type: #{ast.type}"
      end
    end

    def evaluate(ast)
      # Placeholder for evaluation logic
      # This should execute the AST and return a result
      ret = Nihil.new
      lower(ast).each do |stmt|
        ret = evaluate_one stmt
      end
      evaluate_one RECALL[ret]
      ret
    end

    def evaluate_one(stmt)
      case stmt.type
      when :let
        name, value = stmt.value
        @env[name] = value
        puts "Let: #{name} = #{value.inspect}"
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
  #   interpreter = Aua::Interpreter.new
  #   result = interpreter.run("some code")
  #
  # @see Aua::Lex for lexing functionality
  # @see Aua::Parse for parsing functionality
  # @see Aua::Vm for virtual machine execution
  class Interpreter
    def initialize(env = {})
      @env = env
    end

    def lex(code) = Lex.new(code).tokens
    def parse(tokens) = Parse.ast tokens
    def vm = VM.new @env

    def run(code)
      # tokens = lex code
      # ast = parse tokens
      # vm.evaluate ast
      pipeline = [method(:lex), method(:parse), vm.method(:evaluate)]
      pipeline.reduce(code) do |input, step|
        puts "#{step.name}: #{input.inspect}..."
        out = step.call(input)
        puts "#{step.name}: #{input.inspect} -> #{out.inspect}"
        out
      rescue Aua::Error => e
        puts "Error during processing: #{e.message}"
        puts Text.indicate(code, e.message.index(e.message.split.last))
        return Result.err(e, message: e.message)
      end
    end
  end

  # The main entry point for the Aua interpreter.
  #
  # @example
  #   Aua.run("some code")
  def self.run(code)
    Interpreter.new.run(code)
  end
end
