module Aua
  # Provides utility methods for syntax-related tasks.
  module Syntax
    # Token = Data.define(:type, :value)
    class Token < Data.define(:type, :value, :at)
      attr_reader :at
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
      "=" => :equals,
      "#" => :comment,
      ";" => :eos,
      "\n" => :eos,
      "}" => :interpolation_end
    }.freeze

    TWO_CHAR_TOKEN_NAMES = { "**" => :pow }.freeze
    THREE_CHAR_TOKEN_NAMES = { "\"\"\"" => :prompt }.freeze
    KEYWORDS = Set.new(%i[if then else elif]).freeze
  end
end
