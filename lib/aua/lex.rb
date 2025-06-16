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

    # NOTE: - also yields the token to the block if given
    def observe(token, &)
      Aua.logger.debug("observe") do
        "token: \\#{token.type} (value: \\#{token.value.inspect}), at: \\#{token.at.inspect}"
      end

      yield token if block_given?

      # Reset string state after any string-ending token
      return unless %i[str_end].include?(token.type)

      string_machine.inside_string = false
      string_machine.buffer = ""
    end

    def tokenize(&)
      Aua.logger.debug("tokenize") { "Starting lexing \\#{caret} (reading \\#{@doc.size} characters)" }
      string_machine.inside_string = false
      string_machine.pending_tokens ||= [] # : Array[token]
      while @lens.more? || !string_machine.pending_tokens.empty?
        tokenize_ret = tokenize!(&)
        next if tokenize_ret
      end
    end

    def tokenize!(&)
      return handle_pending_tokens(&) unless string_machine.pending_tokens.empty?
      return handle_string_mode(&) if string_machine.inside_string && !string_machine.mode.nil?

      handle_normal_mode(&)
      false
    end

    def handle_pending_tokens(&)
      tok = string_machine.pending_tokens.shift
      if tok
        observe(tok, &)
        check_string_bounds(tok)
      end
      true
    end

    def handle_string_mode(&)
      token = handle.string(string_machine.quote || '"')
      tokens = [*token].compact
      tok, *rest = tokens
      string_machine.pending_tokens.concat(rest) if rest.any?
      return unless tok

      handle_string_mode_token(tok, &)
    end

    def handle_string_mode_token(tok, &)
      observe(tok, &)
      string_machine.inside_string = false if tok.type == :interpolation_start
      return unless tok.type == :interpolation_end

      string_machine.inside!
    end

    def handle_normal_mode(&)
      token = consume_until_acceptance
      tokens = [*token].compact
      string_machine.pending_tokens.concat(tokens[1..] || []) if tokens.size > 1
      tok = tokens.first
      handle_normal_mode_token(tok, &)
    end

    def handle_normal_mode_token(tok, &)
      if tok
        observe(tok, &)
        string_machine.inside_string = true if tok.type == :string
        if tok.type == :interpolation_end
          string_machine.inside_string = true
          string_machine.mode = :body
        end
      elsif @lens.more?
        raise Error, Handle.unexpected_character_message(@lens)
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
        accepted = accept!(characters)
        return accepted if accepted
      end
      nil
    end

    def token_names(len)
      [ONE_CHAR_TOKEN_NAMES, TWO_CHAR_TOKEN_NAMES, THREE_CHAR_TOKEN_NAMES][len - 1]
    end

    def accept!(chars)
      matched_handle = token_names(chars.count).find do |pattern, _token_name|
        pattern_match?(pattern, chars.join)
      end
      return unless matched_handle

      handle.send(matched_handle.last, chars.join)
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

    def check_string_bounds(tok)
      string_machine.inside_string = false if tok.type == :interpolation_start
      return unless tok.type == :interpolation_end

      string_machine.inside!
    end
  end
end
