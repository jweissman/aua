require "rainbow/refinement"
require "aua/text"
require "aua/logger"

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
      ";" => :eos,
      "\n" => :eos,
      "}" => :interpolation_end
    }.freeze

    TWO_CHAR_TOKEN_NAMES = { "**" => :pow }.freeze
    THREE_CHAR_TOKEN_NAMES = { "\"\"\"" => :prompt }.freeze
    KEYWORDS = Set.new(%i[if then else elif]).freeze
  end

  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Encapsulates token logic.
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
        advance while current_char&.match?(/[a-zA-Z0-9_]/)
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
        has_dot, dot_count = consume_number
        check_number_followed_by_identifier
        number_str = @lexer.slice_from(start_pos)
        raise Aua::Error, "Invalid token: multiple dots in number at \\#{@lexer.lens.describe}." if dot_count > 1

        number_token_from_string(number_str, has_dot)
      end

      MAX_STRING_LENGTH = 1024 # Maximum length of a string literal

      # Lexes a string literal, supporting interpolation for double-quoted strings.
      def string(quote = "'", &)
        quote.length.times { advance }
        if quote == '"'
          return string_with_interpolation(&) if block_given?

          raise Error, "Double-quoted/interpolated strings must be lexed with a block."
        else
          # Simple or generative string logic
          chars = consume_string_chars(quote)
          unless current_char == quote.chars.last
            raise Error, "Unterminated string literal (expected closing quote '#{quote}') at " + @lexer.lens.describe
          end

          quote.length.times { advance }
          encode_string(chars, quote: quote)
        end
      end

      private

      def consume_number
        has_dot = false
        dot_count = 0
        while current_char&.match?(/\d|\./)
          if current_char == "."
            dot_count += 1
            has_dot = true
          end
          advance
        end

        [has_dot, dot_count]
      end

      def number_token_from_string(str, has_dot)
        has_dot ? t(:float, str.to_f) : t(:int, str.to_i)
      end

      def consume_string_chars(quote)
        chars = [] # : Array[String]
        test_end = -> { quote.chars.count == 1 ? current_char == quote.chars.first : string_end?(quote.chars) }
        while current_char != "" && chars.length < MAX_STRING_LENGTH
          break if test_end.call

          chars << current_char
          advance
        end
        return chars.join if current_char == quote.chars.last

        raise Error, "Unterminated string literal (expected closing quote '#{quote}') at " + @lexer.lens.describe
      end

      def encode_string(val, quote:)
        case quote
        when "'" then t :simple_str, val
        when "`" then t :raw_str, val
        when '"""' then t :gen_lit, val
        else t :str, val
        end
      end

      def string_end?(quote_chars)
        lookahead = [current_char, next_char, next_next_char].take(quote_chars.length)
        if lookahead == quote_chars
          # For multi-char quotes, shift out the quote chars and advance as needed
          (quote_chars.length - 1).times { advance } if quote_chars.length > 1

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

    # Dispatch manager (lexing entrypoints / first-level handlers).
    class Handler
      def initialize(lexer)
        @lexer = lexer
      end

      def whitespace(chars)
        # Only skip if not a newline
        advance
        return unless chars == "\n"

        t(:eos)
      end

      def identifier(_) = recognize.identifier
      using Rainbow

      def string(quote)
        if quote == '"'
          @string_pending ||= []
          @string_mode ||= :start
          @string_buffer ||= ""
          max_len = 1024

          # Always return from the pending queue if not empty
          return @string_pending.shift unless @string_pending.empty?

          loop do
            case @string_mode
            when :start
              @string_buffer = ""
              advance
              @string_mode = :body
            when :body
              if ["", '"'].include?(current_char)
                token = t(:str_part, @string_buffer) unless @string_buffer.empty?
                @string_buffer = nil
                @string_mode = :end
                return token if token

                next
              elsif current_char == "\\" && next_char == '"'
                @string_buffer << '"'
                advance(2)
              elsif current_char == "$" && next_char == "{"
                advance(2)
                token = t(:str_part, @string_buffer) unless @string_buffer.empty?
                @string_buffer = ""
                return [token, t(:interpolation_start, "${")] if token

                return t(:interpolation_start, "${")

              # elsif current_char == "$" && next_char == "{"
              #   advance(2)

              #   token = t(:str_part, @string_buffer)
              #   @string_buffer = ""
              #   return [token, t(:interpolation_start, "${")]

              else
                @string_buffer << current_char
                advance
                if @string_buffer.length >= max_len
                  raise Error,
                        "Unterminated string literal (of length #{@string_buffer.length}) at " + lens.describe
                end
              end
            when :end
              advance
              @string_mode = nil
              return t(:str_end, "")
            end
          end
        else
          recognize.string(quote)
        end
      end

      def prompt(_) = recognize.string('"""')
      def number(_) = recognize.number_lit

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

      def eos(_)
        advance
        t(:eos)
      end

      def interpolation_end(_)
        advance
        t(:interpolation_end, "}")
      end

      def unexpected(_char) = raise(Error, Handler.unexpected_character_message(lens))

      def self.unexpected_character_message(the_lens)
        hint = "The character #{the_lens.current_char.inspect} is not valid in the current context."
        msg = the_lens.identify(
          message: "Invalid token: unexpected character",
          hint:
        )
        Aua.logger.warn msg
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

    # Returns true if we should resume string mode after an interpolation_end.
    # This is true if we are in the middle of a double-quoted string (i.e., @string_mode is not nil)
    def should_resume_string
      !!(@string_mode && @string_mode != :end && !@string_mode.nil?)
    end

    def tokenize(&)
      @inside_string = false
      @pending_tokens ||= []
      while @lens.more? || !@pending_tokens.empty?
        # if Aua.testing?
        Aua.logger.debug "Lens -- #{@lens.describe}"
        if @pending_tokens.empty?
          Aua.logger.debug "No pending tokens, consuming next character."
        else
          Aua.logger.debug "Pending tokens: #{@pending_tokens.map(&:type).join(", ")}"
        end
        # end
        unless @pending_tokens.empty?
          tok = @pending_tokens.shift
          if tok
            yield(tok)
            # After interpolation_start, we want to parse the interpolation (not string)
            @inside_string = false if tok.type == :interpolation_start
            # After interpolation_end, always resume string mode for double-quoted strings
            @inside_string = true if tok.type == :interpolation_end
          end
          next
        end

        if @inside_string && !@string_mode.nil?
          token = handle.string('"')
          tokens = token.is_a?(Array) ? token : [token]
          @pending_tokens.concat(tokens[1..]) if tokens.size > 1
          tok = tokens.first
          if tok
            yield(tok)
            # After interpolation_start, we want to parse the interpolation (not string)
            @inside_string = false if tok.type == :interpolation_start
            # After interpolation_end, always resume string mode for double-quoted strings
            @inside_string = true if tok.type == :interpolation_end
          end
        else
          token = consume_until_acceptance
          tokens = token.is_a?(Array) ? token : [token]
          @pending_tokens.concat(tokens[1..]) if tokens.size > 1
          tok = tokens.first
          if tok
            yield(tok)
            @inside_string = true if tok.type == :string
            @inside_string = true if tok.type == :interpolation_end
          else
            # Only raise if there is still non-ignorable input
            raise Error, Handler.unexpected_character_message(@lens) if @lens.more?

            break

          end
        end
      end
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

      return unless matched_handler

      Aua.logger.debug "Matched handler: #{matched_handler.inspect}"
      handle.send(matched_handler.last, chars.join)
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
