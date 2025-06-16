require "aua/lex/handle/string_machine"

module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Dispatch manager (lexing entrypoints / first-level Handles).
    class Handle
      using Rainbow

      def initialize(lexer)
        @lexer = lexer
      end

      def whitespace(chars)
        advance
        return unless chars == "\n"

        t(:eos)
      end

      def comment(_chars)
        advance while lens.current_char != "\n" && !lens.eof?
        advance if lens.current_char == "\n"
        nil
      end

      def identifier(_) = recognize.identifier

      def string(quote)
        Aua.logger.debug("Handle#string") do
          "Starting string lexing with quote: #{quote.inspect} at position #{current_pos}"
        end
        string_machine
        # sm.saw_interpolation = false if quote == '"""'
        if interpolative_quote?(quote)
          interpolative_string(quote)
        else
          recognize.string(quote)
        end
      end

      def interpolative_string(quote)
        sm = string_machine
        sm.quote = quote
        sm.max_len = 2048
        return sm.pending_tokens.shift unless sm.pending_tokens.empty?

        sm.spin! do |sm_ret|
          case sm_ret
          when Syntax::Token
            # Aua.logger.debug("Handle#string") do
            #   "Returning token: #{sm_ret.type.inspect} with value: #{sm_ret.value.inspect}"
            # end
            return sm_ret
          when Array
            sm.pending_tokens.concat(sm_ret)
            return sm.pending_tokens.shift
          end
        end
      end

      def prompt(_)
        string('"""') || raise(Error, "Prompt could not be recognized at position #{current_pos}")
      end

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
        (2.times { advance }
         t(:pow))
      end

      def pipe(_)
        advance
        t(:pipe)
      end

      def eos(_)
        advance
        t(:eos)
      end

      def interpolation_end(_)
        advance
        t(:interpolation_end, "}")
      end

      def unexpected(_char) = raise(Error, Handle.unexpected_character_message(lens))

      def self.unexpected_character_message(the_lens)
        hint = "The character \\#{the_lens.current_char.inspect} is not valid in the current context."
        msg = the_lens.identify(
          message: "Invalid token: unexpected character",
          hint:
        )
        Aua.logger.warn msg
        msg
      end

      def string_machine = @lexer.string_machine

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

      private

      def interpolative_quote?(quote)
        # Aua.logger.debug "[Handle#interpolative_quote?] Checking if quote #{quote.inspect} is interpolative"
        ['"""', '"'].include?(quote)
      end
    end
  end
end
