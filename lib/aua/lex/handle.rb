require "aua/lex/handle/string_machine"

module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Dispatch manager (lexing entrypoints / first-level Handles).
    class Handle
      # Initializes the Handle with the lexer instance.

      def initialize(lexer)
        @lexer = lexer
      end

      def whitespace(chars)
        advance
        return unless chars == "\n"

        t(:eos)
      end

      def identifier(_) = recognize.identifier
      using Rainbow

      def interpolative_quote?(quote)
        # Aua.logger.debug "[Handle#interpolative_quote?] Checking if quote #{quote.inspect} is interpolative"
        ['"""', '"'].include?(quote)
      end

      def string(quote)
        Aua.logger.debug("Handle#string") do
          "Starting string lexing with quote: #{quote.inspect} at position #{current_pos}"
        end
        # Aua.logger.debug "[Handle#string] Current character: #{current_char.inspect}, next character: #{next_char.inspect}"
        sm = string_machine
        sm.saw_interpolation = false if quote == '"""'
        if interpolative_quote?(quote)
          sm.pending_tokens ||= []
          sm.mode ||= :start
          sm.buffer ||= ""
          sm.quote = quote
          sm.max_len = 2048
          return sm.pending_tokens.shift unless sm.pending_tokens.empty?

          until (sm.buffer&.length || 0) >= sm.max_len || sm.mode.nil?
            sm_ret = sm.perform!
            unless sm_ret == :continue
              Aua.logger.debug("Handle#string") do
                "#{quote} [#{sm.mode}] curr/next/skip=[ >#{current_char} / >#{next_char} / >#{next_next_char} ]"
              end
            end

            if sm_ret == :continue
              # Aua.logger.debug "[Handle#string] Continuing in mode=#{sm.mode.inspect}, buffer=#{sm.buffer.inspect}"
              next
            elsif sm_ret.is_a?(Syntax::Token)
              Aua.logger.debug("Handle#string") do
                "Returning token: #{sm_ret.type.inspect} with value: #{sm_ret.value.inspect}"
              end
              return sm_ret
            elsif sm_ret.is_a?(Array)
              Aua.logger.debug("Handle#string") { "Returning array of tokens: #{sm_ret.map(&:type).join(", ")}" }
              sm.pending_tokens.concat(sm_ret)
              return sm.pending_tokens.shift
            else
              Aua.logger.debug("Handle#string") do
                "StringMachine returned #{sm_ret}, continuing in mode=#{sm.mode.inspect}"
              end
            end
          end
        else
          recognize.string(quote)
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

      def comment(_chars)
        advance while lens.current_char != "\n" && !lens.eof?
        advance if lens.current_char == "\n"
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
    end
  end
end
