module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Dispatch manager (lexing entrypoints / first-level handlers).
    class Handler
      class StringMachine
        attr_accessor :mode, :buffer, :quote, :pending_tokens, :saw_interpolation, :inside_string, :max_len

        def initialize(lexer)
          @lexer = lexer
          reset!
        end

        def reset!
          @mode = :start
          @buffer = ""
          @quote = nil
          @pending_tokens = []
          @saw_interpolation = false
          @max_len = 2048
        end

        def advance(inc = 1) = @lexer.advance(inc)
        def current_char = @lexer.lens.current_char
        def next_char = @lexer.lens.peek
        def next_next_char = @lexer.lens.peek_n(2).last
        def current_pos = @lexer.lens.current_pos
        def t(...) = @lexer.t(...)

        def flush
          val = @buffer
          @buffer = ""
          val
        end

        def append(char) = @buffer << char

        def at_str_end?(quote: @quote)
          curr_char = current_char
          nxt_char = next_char
          skip_char = next_next_char
          if quote == '"""'
            curr_char == '"' && nxt_char == '"' && skip_char == '"'
          else
            ['"', ""].include?(curr_char)
          end
        end

        def perform!
          perform(@mode)
        end

        protected

        def perform(state)
          Aua.logger.debug "[StringMachine#perform] Performing state: #{state.inspect} at position #{current_pos}"
          raise Error, "Invalid string machine state: #{state.inspect}" unless %i[start body end].include?(state)
          send state
        end

        def start
          @buffer = ""
          @mode = :body
          if @quote == '"""'
            advance(3)
          else
            advance
          end
        end

        def end
          if @quote == '"""' && !@saw_interpolation
            @mode = nil
            return t(:gen_lit, @buffer)
          end
          Aua.logger.debug "[Handler#string] mode=end, returning :str_end"
          advance
          @mode = nil
          @pending_tokens&.clear
          t(:str_end, "")
        end

        def body
          max_len = @max_len || 24

          # End triple-quoted string
          if @quote == '"""' && current_char == '"' && next_char == '"' && next_next_char == '"'
            Aua.logger.debug "close str -- mode=body, gen=#{@quote == '"""'}"
            Aua.logger.debug "saw_interpolation=#{@saw_interpolation.inspect}, buffer=#{@buffer.inspect}"
            token = if @saw_interpolation
                      t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
                    else
                      @mode = nil
                      t(:gen_lit, @buffer)
                    end
            @buffer = nil
            @mode = :end
            advance(3)
            Aua.logger.debug "[Handler#string] ending with token type=#{token&.type}"
            return token if token
            return :continue
          end

          # End single/double-quoted string
          if ["", '"'].include?(current_char)
            token = t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
            @buffer = nil
            @mode = :end
            return token if token
            return :continue
          end

          # Escape sequence
          if current_char == "\\" && next_char == '"'
            @buffer << '"'
            advance(2)
            return :continue
          end

          # Interpolation
          if current_char == "$" && next_char == "{"
            @saw_interpolation = true if @quote == '"""'
            Aua.logger.debug "[Handler#string] Found interpolation start at pos=#{current_pos}, buffer=#{@buffer.inspect}"
            advance(2)
            token = t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
            @buffer = ""
            # Place interpolation_start token at the END of pending_tokens, so it is yielded AFTER any str_part
            if token
              @pending_tokens.unshift(t(:interpolation_start, "${"))
              return token
            end
            return t(:interpolation_start, "${")
          end

          # Normal character
          @buffer << current_char
          advance
          if @buffer && @buffer.length >= max_len
            raise Error,
                  "Unterminated string literal (of length #{@buffer.length}) at " + @lexer.lens.describe
          end
          :continue
        end
      end

      # Initializes the handler with the lexer instance.

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
        Aua.logger.debug "[Handler#interpolative_quote?] Checking if quote #{quote.inspect} is interpolative"
        ['"""', '"'].include?(quote)
      end

      def string(quote)
        Aua.logger.debug "[Handler#string] Starting string lexing with quote: #{quote.inspect} at position #{current_pos}"
        Aua.logger.debug "[Handler#string] Current character: #{current_char.inspect}, next character: #{next_char.inspect}"
        sm = string_machine
        if quote == '"""'
          sm.saw_interpolation = false
        end
        if interpolative_quote?(quote)
          sm.pending_tokens ||= []
          sm.mode ||= :start
          sm.buffer ||= ""
          sm.quote = quote
          sm.max_len = 2048
          return sm.pending_tokens.shift unless sm.pending_tokens.empty?
          until (sm.buffer&.length || 0) >= sm.max_len || sm.mode.nil?
            Aua.logger.debug "#{quote} [#{sm.mode}] curr/next/skip=[ #{current_char} #{next_char} #{next_next_char} ]"
            sm_ret = sm.perform!
            if sm_ret == :continue
              Aua.logger.debug "[Handler#string] Continuing in mode=#{sm.mode.inspect}, buffer=#{sm.buffer.inspect}"
              next
            elsif sm_ret.is_a?(Syntax::Token)
              Aua.logger.debug "[Handler#string] Returning token: #{sm_ret.type.inspect} with value: #{sm_ret.value.inspect}"
              return sm_ret
            elsif sm_ret.is_a?(Array)
              Aua.logger.debug "[Handler#string] Returning array of tokens: #{sm_ret.map(&:type).join(", ")}"
              sm.pending_tokens.concat(sm_ret)
              return sm.pending_tokens.shift
            else
              Aua.logger.debug "[Handler#string] StringMachine returned #{sm_ret.inspect}, continuing in mode=#{sm.mode.inspect}"
            end
          end
        else
          recognize.string(quote)
        end
      end

      def prompt(_) = string('"""')
      def number(_) = recognize.number_lit
      def minus(_) = (advance; t(:minus))
      def plus(_) = (advance; t(:plus))
      def star(_) = (advance; t(:star))
      def slash(_) = (advance; t(:slash))
      def lparen(_) = (advance; t(:lparen))
      def rparen(_) = (advance; t(:rparen))
      def equals(eql) = (advance; t(:equals, eql))
      def pow(_) = (2.times { advance }; t(:pow))

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

      def unexpected(_char) = raise(Error, Handler.unexpected_character_message(lens))

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
