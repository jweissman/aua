module Aua
  # Provides utility methods for syntax-related tasks.
  module Syntax
    Token = Data.define(:type, :value)

    # Creates a new token with the given type and optional value.
    def t(type, value = nil) = Token.new(type:, value:)
  end

  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Encapsulates specific logic for recognizing different types of tokens.
    class Recognizer
      include Syntax

      def initialize(lexer)
        @lexer = lexer
      end

      def current_char = @lexer.current_char
      def advance = @lexer.advance
      def eof? = @lexer.eof?

      # Lexes an identifier or boolean literal.
      #
      # @return [Token] The token representing the identifier or boolean literal.
      # Lexes an identifier or boolean literal.
      def identifier
        start_pos = @lexer.current_pos #  - 1
        advance while current_char&.match?(/[a-zA-Z_]/)
        # value = @doc.slice(start_pos, @doc.position - start_pos)
        value = @lexer.slice_from(start_pos)
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
        start_pos = @lexer.current_pos
        has_dot = false
        while current_char&.match?(/\d|\./)
          has_dot = true if current_char == "."
          advance
        end
        # After number, if next char is a letter, that's invalid (e.g. 123abc)
        if current_char&.match?(/[a-zA-Z_]/)
          raise Aua::Error,
                "Invalid token: number immediately followed by identifier at line \\#{@lexer.current_line}, column \\#{@lexer.current_column}"
        end

        # number_str = @doc.slice(start_pos, @doc.position - start_pos)
        number_str = @lexer.slice_from(start_pos)
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
    end

    include Syntax

    MAX_TOKENS = 10_000

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
    end

    def advance = @doc.advance
    def current_pos    = @doc.position
    def current_line   = @doc.cursor.line
    def current_column = @doc.cursor.column
    def current_char   = @doc.peek

    def slice_from(start) = @doc.slice(start, @doc.position - start)

    # Enumerator-based token stream for memory efficiency and streaming.
    def tokenize(&)
      puts "tokenize: #{current_char.inspect} at line #{current_line}, column #{current_column}"
      accept(&) until @doc.finished?
    end

    TOKEN_HANDLERS = {
      /\s/ => :handle_whitespace,
      /\d/ => :handle_number,
      /[a-zA-Z_]/ => :handle_identifier,
      '"' => :handle_string,
      "-" => :handle_minus,
      "+" => :handle_plus,
      "*" => :handle_star,
      "/" => :handle_slash,
      "(" => :handle_lparen,
      ")" => :handle_rparen,
      "=" => :handle_equals
    }.freeze

    def accept(&)
      TOKEN_HANDLERS.each do |pattern, handler|
        case pattern
        when Regexp then return send(handler, &) if current_char&.match?(pattern)
        when String then return send(handler, &) if current_char == pattern
        end
      end
      handle_unexpected if current_char
      nil
    end

    # --- Handler methods: always yield or return nil ---
    def handle_whitespace
      advance
      nil
    end

    def handle_identifier
      yield recognize.identifier
    end

    def handle_string
      yield recognize.string
    end

    def handle_minus
      advance
      yield t(:minus)
    end

    def handle_plus
      advance
      yield t(:plus)
    end

    def handle_star
      advance
      yield t(:star)
    end

    def handle_slash
      advance
      yield t(:slash)
    end

    def handle_lparen
      advance
      yield t(:lparen)
    end

    def handle_rparen
      advance
      yield t(:rparen)
    end

    def handle_number
      num = recognize.number_lit
      yield num
    end

    def handle_equals
      advance
      yield t(:equals)
    end

    def handle_unexpected = raise(Error, unexpected_character_message)

    def recognize
      @recognizer ||= Recognizer.new(self)
    end
  end
end
