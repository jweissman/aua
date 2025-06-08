# frozen_string_literal: true

require "rainbow/refinement"

module Aua
  # Provides utility methods for syntax-related tasks.
  module Syntax
    # Token = Data.define(:type, :value)
    class Token < Data.define(:type, :value, :at)
      attr_reader :at
    end

    ONE_CHAR_TOKEN_NAMES = {
      /\s/ => :whitespace,
      /\d/ => :number,
      /[a-zA-Z_]/ => :identifier,
      '"' => :string,
      "-" => :minus,
      "+" => :plus,
      "*" => :star,
      "/" => :slash,
      "(" => :lparen,
      ")" => :rparen,
      "=" => :equals
    }.freeze

    TWO_CHAR_TOKEN_NAMES = { "**" => :pow }.freeze

    THREE_CHAR_TOKEN_NAMES = {
      "\"\"\"" => :prompt
    }.freeze

    KEYWORDS = Set.new(%i[if then else elif]).freeze
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

      def advance(inc = 1) = @lexer.advance(inc)
      def current_char = @lexer.lens.current_char
      def next_char = @lexer.lens.peek
      def next_next_char = @lexer.lens.peek_n(2).last
      def current_pos = @lexer.lens.current_pos
      def eof? = @lexer.eof?

      # Creates a new token with the given type and optional value.
      def t(type, value = nil, at: @lexer.caret) = Syntax::Token.new(type:, value:, at: at || @lexer.caret)

      # Lexes an identifier or boolean literal.
      #
      # @return [Token] The token representing the identifier or boolean literal.
      # Lexes an identifier or boolean literal.
      def identifier
        start_pos = current_pos #  - 1
        advance while current_char&.match?(/[a-zA-Z_]/)
        value = @lexer.slice_from(start_pos)
        return t(:keyword, value) if KEYWORDS.include?(value.to_sym)

        case value
        when "true", "false" then t(:bool, value == "true")
        when "nihil" then t(:nihil, true)
        else
          t(:id, value)
        end
      end

      # Lexes an integer or floating-point literal.
      def number_lit
        start_pos = current_pos
        has_dot = false
        while current_char&.match?(/\d|\./)
          has_dot = true if current_char == "."
          advance
        end
        check_number_followed_by_identifier
        number_str = @lexer.slice_from(start_pos)
        number_token_from_string(number_str, has_dot)
      end

      def number_token_from_string(str, has_dot)
        has_dot ? t(:float, str.to_f) : t(:int, str.to_i)
      end

      # Lexes a string literal, accumulating characters between quotes.
      MAX_STRING_LENGTH = 65_536
      def string(quote = '"')
        advance
        chars = consume_string_chars(quote)

        advance # skip closing quote
        raise Error, "Unterminated string literal (of length #{chars.length})" if chars.length >= MAX_STRING_LENGTH

        encode_string(chars, quote:)
      end

      private

      def consume_string_chars(quote)
        chars = []
        while current_char != "" && chars.length < MAX_STRING_LENGTH
          chars << current_char
          advance
          break if string_end?(quote.chars, chars)
        end

        return chars.join if current_char == quote.chars.last

        raise Error, "Unterminated string literal (expected closing quote '#{quote}') at #{@lexer.lens.describe}"
      end

      def encode_string(val, quote:)
        case quote
        when "'" then t :char, val
        when "`" then t :raw_str, val
        when '"""' then t :gen_lit, val
        else t :str, val
        end
      end

      def string_end?(quote_chars, chars)
        lookahead = [current_char, next_char, next_next_char].take(quote_chars.length)
        if lookahead == quote_chars
          # For multi-char quotes, shift out the quote chars and advance as needed
          if quote_chars.length > 1
            chars.shift(quote_chars.length - 1)
            (quote_chars.length - 1).times { advance }
          end
          true
        else
          false
        end
      end

      def check_number_followed_by_identifier
        return unless current_char&.match?(/[a-zA-Z_]/)

        raise Aua::Error, invalid_token_message("number immediately followed by identifier")
      end

      def invalid_token_message(what)
        "Invalid token: #{what} at #{@lexer.lens.describe}."
      end
    end

    # Provides a lens for inspecting the current position in the source code.
    class Lens
      def initialize(doc)
        @doc = doc
      end

      def eof? = @doc.finished?
      def peek = @doc.peek
      def peek_n(inc) = @doc.peek_n(inc)

      # Current position and character information
      def current_pos    = @doc.position || 0
      def current_line   = @doc.cursor.line
      def current_column = @doc.cursor.column
      def current_char   = @doc.current || ""

      def describe = "#{current_line}:#{current_column} #{describe_character(current_char)}"

      def describe_character(char)
        case char
        when ";" then "semicolon"
        else "character #{char.inspect}"
        end
      end

      def identify(message: nil, hint: nil)
        current_char = @lens.current_char
        current_line = @lens.current_line
        current_column = @lens.current_column

        <<~ERROR
          #{message}: #{describe_character(current_char)} at line #{current_line}, column #{current_column}.
          #{@doc.indicate.join("\n")}
          #{hint || "Have you tried turning it off and on again?"}
        ERROR
      end
    end

    include Syntax

    attr_reader :lens

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
      @lens = Lens.new(@doc)
    end

    def inspect = "#<#{self.class.name}@#{@lens.describe}>"
    def tokens = enum_for(:tokenize).lazy
    def advance(inc = 1) = @doc.advance(inc)
    def slice_from(start) = @doc.slice(start, @doc.position - start)
    def caret = @doc.caret
    def t(type, value = nil, at: caret) = Token.new(type:, value:, at: at || caret)

    # Enumerator-based token stream for memory efficiency and streaming.
    def tokenize
      until @lens.eof?
        token = accept

        yield token unless token.nil?
      end
    end

    def accept(&)
      current_char = @lens.current_char
      peek_char, next_peek_char = @doc.peek_n(2)
      chars = [current_char, peek_char, next_peek_char]
      (1..chars.size).map { |n| chars.take(n).compact }.reverse
                     .each do |characters|
        accepted = accept_n(characters)
        return accepted if accepted
      end
      nil
    end

    def token_names(len)
      [ONE_CHAR_TOKEN_NAMES, TWO_CHAR_TOKEN_NAMES, THREE_CHAR_TOKEN_NAMES][len - 1]
    end

    def accept_n(chars)
      token_names(chars.count).each do |pattern, token_name|
        handler = "handle_#{token_name}"
        case pattern
        when Regexp
          return send(handler) if chars.join&.match?(pattern)
        when String
          return send(handler) if chars.join == pattern
        end
      end
      nil
    end

    # --- Handler methods: always yield or return nil ---
    def handle_whitespace = advance
    def handle_identifier = recognize.identifier
    def handle_string = recognize.string
    def handle_prompt = recognize.string('"""')

    def handle_minus
      advance
      t(:minus)
    end

    def handle_plus
      advance
      t(:plus)
    end

    def handle_star
      advance
      t(:star)
    end

    def handle_slash
      advance
      t(:slash)
    end

    def handle_lparen
      advance
      t(:lparen)
    end

    def handle_rparen
      advance
      t(:rparen)
    end

    def handle_number
      recognize.number_lit
    end

    def handle_equals
      advance
      t(:equals)
    end

    def handle_pow
      2.times { advance }
      t(:pow)
    end

    def handle_unexpected = raise(Error, unexpected_character_message)
    def recognize = @recognize ||= Recognizer.new(self)

    def unexpected_character_message
      @lens.identify(
        message: "Unexpected character",
        hint: "This character is not valid in the current context."
      )
    end
  end
end
