module Aua
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
        raise Error, "Double-quoted/interpolated strings must be lexed with a block." if quote == '"'

        # Simple or generative string logic

        chars = consume_string_chars(quote)
        unless current_char == quote.chars.last
          raise Error, "Unterminated string literal (expected closing quote '#{quote}') at " + @lexer.lens.describe
        end

        quote.length.times { advance }
        encode_string(chars, quote: quote)
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
        Aua.logger.info "[Recognizer#encode_string] Encoding string with quote: #{quote.inspect}, value: #{val.inspect}"
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
  end
end
