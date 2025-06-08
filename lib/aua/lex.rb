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
      "'" => :string,
      "-" => :minus,
      "+" => :plus,
      "*" => :star,
      "/" => :slash,
      "(" => :lparen,
      ")" => :rparen,
      "=" => :equals,
      "#" => :comment,
    }.freeze

    TWO_CHAR_TOKEN_NAMES = { "**" => :pow }.freeze

    THREE_CHAR_TOKEN_NAMES = {
      "\"\"\"" => :prompt,
    }.freeze

    KEYWORDS = Set.new(%i[if then else elif]).freeze
  end

  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Handle lexing entrypoints, recognizing tokens and managing the lexer state.
    class Handler
      def initialize(lexer)
        @lexer = lexer
      end

      def whitespace(_) = advance
      def identifier(_) = recognize.identifier
      def string(quote) = recognize.string(quote)
      def prompt(_) = recognize.string('"""')

      def minus(_)
        advance
        t(:minus)
      end

      def plus(_)
        advance
        t(:plus)
      end

      def star(_)
        advance
        t(:star)
      end

      def slash(_)
        advance
        t(:slash)
      end

      def lparen(_)
        advance
        t(:lparen)
      end

      def rparen(_)
        advance
        t(:rparen)
      end

      def number(_)
        recognize.number_lit
      end

      def equals(eql)
        advance
        t(:equals, eql)
      end

      def pow(_)
        2.times { advance }
        t(:pow)
      end

      def comment(_chars)
        advance while lens.current_char != "\n" && !lens.eof?
        advance if lens.current_char == "\n" # skip the newline itself
        nil
      end

      def unexpected(_char) = raise(Error, Handler.unexpected_character_message(lens))

      def self.unexpected_character_message(the_lens)
        hint = "The character #{the_lens.current_char.inspect} is not valid in the current context."
        msg = the_lens.identify(
          message: "Invalid token: unexpected character",
          hint:,
        )
        puts msg
        msg
      end

      protected

      def lens = @lexer.lens
      def advance(inc = 1) = @lexer.advance(inc)
      def recognize = @lexer.recognize
      def t(type, value = nil, at: @lexer.caret) = @lexer.t(type, value, at:)
      def current_pos = lens.current_pos
      def current_char = lens.current_char
      def next_char = lens.peek
      def next_next_char = lens.peek_n(2).last
      def eof? = lens.eof?
    end

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
        start_pos = current_pos
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

      def string(quote = "'")
        advance
        chars = consume_string_chars(quote)

        advance # skip closing quote
        raise Error, "Unterminated string literal (of length #{chars.length})" if chars.length >= MAX_STRING_LENGTH

        encode_string(chars, quote:)
      end

      private

      def consume_string_chars(quote)
        chars = [] # : Array[String]
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
        when "'" then t :simple_str, val
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
      def more? = !eof?
      def peek = @doc.peek
      def peek_n(inc) = @doc.peek_n(inc)

      # Current position and character information
      def current_pos = @doc.position || 0
      def current_line = @doc.cursor.line
      def current_column = @doc.cursor.column
      def current_char = @doc.current || ""

      def describe = "#{current_line}:#{current_column} #{describe_character(current_char)}"

      def describe_character(char)
        case char
        when ";" then "semicolon"
        else "character #{char.inspect}"
        end
      end

      def identify(message: nil, hint: nil)
        <<~ERROR
          #{message} at line #{current_line}, column #{current_column}:

          #{@doc.indicate.join("\n")}
          #{hint || describe_character(current_char)}
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

    def tokens = enum_for(:tokenize).lazy
    def advance(inc = 1) = @doc.advance(inc)
    def recognize = @recognize ||= Recognizer.new(self)
    def inspect = "#<#{self.class.name}@#{@lens.describe}>"
    def caret = @doc.caret
    def slice_from(start) = @doc.slice(start, @doc.position - start)
    def t(type, value = nil, at: caret) = Token.new(type:, value:, at: at || caret)

    private

    def tokenize(&) = (yield_lexeme(&) while @lens.more?)

    def yield_lexeme(&)
      token = consume_until_acceptance
      if token.is_a?(Token)
        yield(token)
        return
      end
      return unless @lens.more?

      raise Error, Handler.unexpected_character_message(@lens) if @lens.current_char
    end

    def consume_until_acceptance(attempts = 16_536)
      token = nil # : Syntax::Token | nil
      while token.nil? && @lens.more? && attempts.positive?
        token = accept
        attempts -= 1
      end
      token
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
      matched_handler = token_names(chars.count).find do |pattern, _token_name|
        pattern_match?(pattern, chars.join)
      end
      handle.send(matched_handler.last, chars.join) if matched_handler
    end

    def pattern_match?(pattern, content)
      case pattern
      when Regexp
        content.match?(pattern)
      when String
        content == pattern
      end
    end

    def handle = @handle ||= Handler.new(self)
  end
end
