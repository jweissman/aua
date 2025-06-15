require "rainbow/refinement"
require "aua/text"
require "aua/logger"
require "aua/syntax"
require "aua/lex/lens"
require "aua/lex/handle"
require "aua/lex/recognizer"

module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
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
    def string_machine = @string_machine ||= Handle::StringMachine.new(self)

    private

    # Returns true if we should resume string mode after an interpolation_end.
    # This is true if we are in the middle of a double-quoted string (i.e., string_machine.mode is not nil)
    def should_resume_string
      !!(string_machine.mode && string_machine.mode != :end && !string_machine.mode.nil?)
    end

    def observe(token)
      Aua.logger.debug "Observed token: \\#{token.type} (value: \\#{token.value.inspect}), at: \\#{token.at.inspect}"

      return unless token.type == :str_end

      string_machine.inside_string = false
      string_machine.mode = :none
    end

    def tokenize(&)
      Aua.logger.debug "Starting lexing \\#{caret} (reading \\#{@doc.size} characters)"
      string_machine.inside_string = false
      string_machine.pending_tokens ||= [] # : Array[token]
      while @lens.more? || !string_machine.pending_tokens.empty?
        Aua.logger.debug "Lens -- \\#{@lens.describe}"
        if string_machine.pending_tokens.empty?
          Aua.logger.debug "No pending tokens, consuming next character."
        else
          Aua.logger.debug "Pending tokens: \\#{string_machine.pending_tokens.map(&:type).join(", ")}"
        end
        # end
        unless string_machine.pending_tokens.empty?
          tok = string_machine.pending_tokens.shift
          if tok
            Aua.logger.debug "Yielding token: \\#{tok.type} (value: \\#{tok.value.inspect}), inside_string=\\#{string_machine.inside_string.inspect}, string_mode=\\#{string_machine.mode.inspect}"
            observe(tok)
            yield(tok)
            string_machine.inside_string = false if tok.type == :interpolation_start
            if tok.type == :interpolation_end
              string_machine.inside_string = true
              string_machine.mode = :body
            end
          end
          next
        end

        if string_machine.inside_string && !string_machine.mode.nil?
          Aua.logger.debug "Resuming string lexing: inside_string=\\#{string_machine.inside_string.inspect}, string_mode=\\#{string_machine.mode.inspect}, current_char=\\#{@lens.current_char.inspect}"
          # Use the correct quote type for resuming string lexing
          token = handle.string(string_machine.quote || '"')
          # tokens = token.is_a?(Array) ? token : [token]
          # string_machine.pending_tokens.concat(tokens[1..] || []) if tokens.size > 1
          # tok = tokens.first
          tokens = [*token].compact
          tok, *rest = tokens
          string_machine.pending_tokens.concat(rest) if rest.any?
          if tok
            Aua.logger.debug "Yielding token (string mode): \\#{tok.type} (value: \\#{tok.value.inspect}), inside_string=\\#{string_machine.inside_string.inspect}, string_mode=\\#{string_machine.mode.inspect}"
            observe(tok)
            yield(tok)
            string_machine.inside_string = false if tok.type == :interpolation_start
            if tok.type == :interpolation_end
              string_machine.inside_string = true
              string_machine.mode = :body
            end
          end
        else
          Aua.logger.debug "Not inside string, consuming next tokens..."
          token = consume_until_acceptance

          # tokens = token.is_a?(Array) ? token : [token]
          tokens = [*token].compact
          string_machine.pending_tokens.concat(tokens[1..] || []) if tokens.size > 1
          tok = tokens.first
          if tok
            yield(tok)
            string_machine.inside_string = true if tok.type == :string
            if tok.type == :interpolation_end
              string_machine.inside_string = true
              string_machine.mode = :body
            end
          else
            Aua.logger.debug "No token accepted, checking for pending tokens."
            # Only raise if there is still non-ignorable input
            raise Error, Handle.unexpected_character_message(@lens) if @lens.more?

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
      matched_Handle = token_names(chars.count).find do |pattern, _token_name|
        pattern_match?(pattern, chars.join)
      end

      return unless matched_Handle

      Aua.logger.debug "Matched Handle: #{matched_Handle.inspect}"
      handle.send(matched_Handle.last, chars.join)
    end

    def pattern_match?(pattern, content)
      case pattern
      when Regexp
        content.match?(pattern)
      when String
        content == pattern
      end
    end

    def handle = @handle ||= Handle.new(self)
  end
end
