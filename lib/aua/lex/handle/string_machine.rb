module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Dispatch manager (lexing entrypoints / first-level Handles).
    class Handle
      class StringMachine
        attr_accessor :mode, :buffer, :quote, :pending_tokens, :saw_interpolation, :inside_string, :max_len

        def initialize(lexer)
          @lexer = lexer
          reset!
        end

        def reset!
          Aua.logger.debug("string_machine#reset") { "Before reset: mode=#{@mode}, inside_string=#{@inside_string}" }
          @mode = :start
          @buffer = ""
          @quote = nil
          @pending_tokens = []
          @saw_interpolation = false
          @max_len = 2048
          @inside_string = false
          Aua.logger.debug("string_machine#reset") { "After reset: mode=#{@mode}, inside_string=#{@inside_string}" }
        end

        def advance(inc = 1) = @lexer.advance(inc)
        def current_char = @lexer.lens.current_char
        def next_char = @lexer.lens.peek
        def next_next_char = @lexer.lens.peek_n(2).last
        def current_pos = @lexer.lens.current_pos

        def t(type, value = nil)
          @lexer.t(type, value, at: @lexer.caret)
        end

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

        def perform! = perform(@mode)

        def spin!(&)
          @pending_tokens ||= [] # : Array[Syntax::Token]
          @mode ||= :start
          until spindown?
            ret = perform!
            next if ret == :continue

            yield ret
          end
        end

        def inside!(mode = :body)
          @inside_string = true
          @mode = mode
        end

        protected

        def spindown? = @buffer&.length.to_i >= @max_len || @mode.nil?

        def perform(state)
          raise Error, "Invalid string machine state: #{state.inspect}" unless %i[start body end none].include?(state)

          send state # unless @mode == :none
        end

        def start
          @buffer = ""
          @mode = :body
          advance @quote.length
        end

        def end
          str_kind = @quote == '"""' ? :gen_end : :str_end
          advance
          @mode = nil
          @pending_tokens&.clear
          t(str_kind, flush)
        end

        def body
          tx = body_transition
          return tx if tx

          # Normal character
          @buffer << current_char
          advance
          if @buffer && @buffer.length >= @max_len
            raise Error,
                  "Unterminated string literal (of length #{@buffer.length}) at " + @lexer.lens.describe
          end
          :continue
        end

        def body_transition
          body_transition_triple_quote          ||
            body_transition_single_double_quote ||
            body_transition_escape              ||
            body_transition_interpolation
        end

        # End triple-quoted string
        def body_transition_triple_quote
          return unless @quote == '"""' && current_char == '"' && next_char == '"' && next_next_char == '"'

          Aua.logger.debug("string_machine#body") do
            "close str -- mode=body, gen=#{@quote == '"""'}, \
              saw_interpolation=#{@saw_interpolation.inspect}, buffer=#{@buffer.inspect}"
          end

          token = t(:gen_lit, @buffer)
          @buffer = nil
          @mode = nil
          advance(3)
          # Reset the string machine state AND inform the lexer we're no longer in a string
          reset!
          @lexer.string_machine.inside_string = false
          Aua.logger.debug("string_machine#body") { "ending with token type=#{token&.type} (reset after gen_lit)" }
          token
        end

        # End single/double-quoted string
        def body_transition_single_double_quote
          # if ["'", '"'].include?(current_char)
          return unless @quote.include?(current_char) && at_str_end?(quote: @quote)

          token = t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
          @buffer = nil
          @mode = :end
          return token if token

          :continue
        end

        # Escape sequence
        def body_transition_escape
          return unless current_char == "\\" && next_char == '"'

          @buffer << '"'
          advance(2)
          :continue
        end

        # Interpolation
        def body_transition_interpolation
          return unless current_char == "$" && next_char == "{"

          @saw_interpolation = true if @quote == '"""'
          Aua.logger.debug("string_machine#body") do
            "Found interpolation start at pos=#{current_pos}, buffer=#{@buffer.inspect}"
          end
          advance(2)

          # Push interpolation context to the lexer's context stack
          @lexer.push_context(:interpolation)
          Aua.logger.debug("string_machine#interpolation") { "Pushed :interpolation to context stack" }

          token = t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
          @buffer = ""

          # Place interpolation_start token at the END of pending_tokens, so it is yielded AFTER any str_part
          if token
            @pending_tokens.unshift(t(:interpolation_start, "${"))
            return token
          end
          t(:interpolation_start, "${")
        end

        # never
        def none = raise Error, "StringMachine is in an invalid state: none"
      end
    end
  end
end
