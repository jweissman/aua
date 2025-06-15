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
          str_kind = :str_end
          str_kind = :gen_end if @quote = '"""' && @saw_interpolation
          advance
          @mode = nil
          @pending_tokens&.clear
          t(str_kind, flush)
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
            Aua.logger.debug "[Handle#string] ending with token type=#{token&.type}"
            if token && token.type == :gen_lit
              reset!
            end
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
            Aua.logger.debug "[Handle#string] Found interpolation start at pos=#{current_pos}, buffer=#{@buffer.inspect}"
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
    end
  end
end
