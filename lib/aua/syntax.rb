module Aua
  # Provides utility methods for syntax-related tasks.
  module Syntax
    # Token = Data.define(:type, :value)
    # Most tokens should have `at` set by their lexer.
    # def t(type, value = nil, at:)
    #   Token.new(type:, value:, at:)
    # end
    class Token < Data.define(:type, :value, :at)
      def inspect = "#{type.upcase}(#{value.inspect})"
    end

    ONE_CHAR_TOKEN_NAMES = {
      /\s/ => :whitespace,
      /\d/ => :number,
      /[a-zA-Z_]/ => :identifier,
      '"' => :string,
      "'" => :string,
      "-" => :minus,
      "+" => :plus,
      "*" => :star,
      "/" => :slash,
      "(" => :lparen,
      ")" => :rparen,
      "{" => :lbrace,
      "}" => :rbrace,
      "[" => :lbracket,
      "]" => :rbracket,
      ":" => :colon,
      "," => :comma,
      "." => :dot,
      "=" => :equals,
      "<" => :lt,
      ">" => :gt,
      "!" => :not,
      "&" => :and_char,
      "#" => :comment,
      ";" => :eos,
      "\n" => :eos,
      "|" => :pipe,
      "~" => :tilde
    }.freeze

    TWO_CHAR_TOKEN_NAMES = { "**" => :pow, "==" => :eq, "!=" => :neq, ">=" => :gte, "<=" => :lte, "&&" => :and,
                             "||" => :or }.freeze
    THREE_CHAR_TOKEN_NAMES = { "\"\"\"" => :prompt }.freeze
    KEYWORDS = Set.new(%i[if then else elif as type while end fun]).freeze
  end
end
