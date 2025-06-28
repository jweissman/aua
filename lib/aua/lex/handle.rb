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

      def tilde(_)
        advance
        t(:tilde)
      end

      def eos(_)
        advance
        t(:eos)
      end

      def eq(_)
        2.times { advance }
        # maybe should be eqeq or similar?
        t(:eq)
      end

      def neq(_)
        2.times { advance }
        t(:neq)
      end

      def interpolation_end(_)
        # Context-aware brace handling using the context stack
        Aua.logger.debug("interpolation_end") do
          "Context stack before pop: #{@lexer.instance_variable_get(:@context_stack).inspect}"
        end
        context = @lexer.pop_context
        Aua.logger.debug("interpolation_end") do
          stack = @lexer.instance_variable_get(:@context_stack)
          "Popped context: #{context.inspect}, remaining stack: #{stack.inspect}"
        end
        advance

        case context
        when :interpolation
          t(:interpolation_end, "}")
        when :object_literal
          t(:rbrace, "}")
        else
          # Fallback: check the old string machine approach
          Aua.logger.debug("interpolation_end") do
            inside = string_machine.inside_string
            saw = string_machine.saw_interpolation
            "Fallback - inside_string: #{inside}, saw_interpolation: #{saw}"
          end
          if string_machine.inside_string || string_machine.saw_interpolation
            t(:interpolation_end, "}")
          else
            t(:rbrace, "}")
          end
        end
      end

      def lbrace(_)
        # Push object literal context when we see { outside of interpolation
        @lexer.push_context(:object_literal) unless @lexer.in_interpolation?
        advance
        t(:lbrace, "{")
      end

      def rbrace(_)
        # Context-aware brace handling
        Aua.logger.debug("rbrace") do
          stack = @lexer.instance_variable_get(:@context_stack)
          "Context stack before pop: #{stack.inspect}"
        end
        context = @lexer.pop_context
        Aua.logger.debug("rbrace") do
          stack = @lexer.instance_variable_get(:@context_stack)
          "Popped context: #{context.inspect}, remaining stack: #{stack.inspect}"
        end
        advance

        case context
        when :interpolation
          Aua.logger.debug("rbrace") { "Returning interpolation_end token" }
          t(:interpolation_end, "}")
        when :object_literal
          t(:rbrace, "}")
        else
          # Fallback: check the old string machine approach
          Aua.logger.debug("rbrace") do
            inside = string_machine.inside_string
            saw = string_machine.saw_interpolation
            "Fallback - inside_string: #{inside}, saw_interpolation: #{saw}"
          end
          if string_machine.inside_string || string_machine.saw_interpolation
            Aua.logger.debug("rbrace") { "Fallback returning interpolation_end token" }
            t(:interpolation_end, "}")
          else
            Aua.logger.debug("rbrace") { "Returning rbrace token" }
            t(:rbrace, "}")
          end
        end
      end

      def colon(_)
        advance
        t(:colon, ":")
      end

      def comma(_)
        advance
        t(:comma, ",")
      end

      def lbracket(_)
        advance
        t(:lbracket, "[")
      end

      def rbracket(_)
        advance
        t(:rbracket, "]")
      end

      def dot(_)
        # Check if this is a valid context for a dot
        # Valid contexts: after identifier/value (member access) or before digit (decimal)

        # Look behind to see what came before
        # This is tricky without lexer lookahead, so let's check the next character
        if next_char =~ /\d/
          # This might be a decimal number like .42, which should be an error
          # Let the number lexer handle this and potentially error
          unexpected(".")
          # This line never executes, but Steep needs a return path
        else
          # This is likely member access, allow it
          advance
        end
        t(:dot, ".")
      end

      def gt(_)
        advance
        t(:gt)
      end

      def lt(_)
        advance
        t(:lt)
      end

      def gte(_)
        2.times { advance }
        t(:gte)
      end

      def lte(_)
        2.times { advance }
        t(:lte)
      end

      def not(_)
        advance
        t(:not)
      end

      def and_char(_)
        advance
        t(:and_char)
      end

      def and(_)
        2.times { advance }
        t(:and)
      end

      def or(_)
        2.times { advance }
        t(:or)
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
      def t(type, value = nil) = @lexer.t(type, value)
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
