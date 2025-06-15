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

        def perform!
          perform(@mode)
        end

        protected

        def perform(state)
          # Aua.logger.debug "[StringMachine#perform] Performing state: #{state.inspect} at position #{current_pos}"
          raise Error, "Invalid string machine state: #{state.inspect}" unless %i[start body end none].include?(state)

          send state # unless @mode == :none
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
          str_kind = :str_end
          str_kind = :gen_end if (@quote = @saw_interpolation)
          advance
          @mode = nil
          @pending_tokens&.clear
          t(str_kind, flush)
        end

        def body
          max_len = @max_len || 24

          # End triple-quoted string
          if @quote == '"""' && current_char == '"' && next_char == '"' && next_next_char == '"'
            Aua.logger.debug("string_machine#body") do
              "close str -- mode=body, gen=#{@quote == '"""'}, \
              saw_interpolation=#{@saw_interpolation.inspect}, buffer=#{@buffer.inspect}"
            end

            if @saw_interpolation
              token = t(:str_part, @buffer) unless @buffer.nil? || @buffer.empty?
              @buffer = nil
              @mode = :end
              advance(3)
              Aua.logger.debug("string_machine#body") { "ending with token type=#{token&.type}" }
              return token if token

              return :continue
            else
              token = t(:gen_lit, @buffer)
              @buffer = nil
              @mode = nil
              advance(3)
              reset!
              Aua.logger.debug("string_machine#body") { "ending with token type=#{token&.type} (reset after gen_lit)" }
              return token
            end
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
            Aua.logger.debug("string_machine#body") do
              "Found interpolation start at pos=#{current_pos}, buffer=#{@buffer.inspect}"
            end
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

        # never
        def none
          raise Error, "StringMachine is in an invalid state: none"
          # advance
        end
      end
    end
  end
end
