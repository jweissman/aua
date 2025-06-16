# Aua is a programming language and interpreter written in Ruby...
module Aua
  # Grammar helpers for constructing AST nodes.
  module Grammar
    PRIMARY_NAMES = {
      lparen: :parens,
      id: :id,
      int: :int,
      float: :float,
      bool: :bool,
      str: :str,
      nihil: :nihil,
      gen_lit: :generative_lit,
      simple_str: :simple_str,
      str_start: :str_start,
      str_part: :str_part,
      str_end: :str_end
    }.freeze

    # Operator precedence (higher number = higher precedence)
    BINARY_PRECEDENCE = {
      as: 0, # typecast has lowest precedence (looser than arithmetic, tighter than assignment)
      plus: 1, minus: 1,
      star: 2, slash: 2,
      pow: 3
    }.freeze

    def s(type, *values)
      normalized_values = normalize_maybe_list(values)
      at = if defined?(@current_token) && @current_token.respond_to?(:location) && @current_token.location
             @current_token.location
           else
             Aua::Text::Cursor.new(0, 0)
           end
      AST::Node.new(type:, value: normalized_values, at: at)
    end

    def normalize_maybe_list(values)
      return nil if values.empty?

      values.length == 1 ? values.first : values
    end

    # A class for parsing primitive values in Aua.
    class Primitives
      include Grammar

      def initialize(parse)
        @parse = parse
      end

      def parse_id = parse_one(:id)
      def parse_int = parse_one(:int)
      def parse_float = parse_one(:float)
      def parse_bool = parse_one(:bool)
      def parse_str = parse_one(:str)

      def parse_nihil = parse_one(:nihil)
      def parse_simple_str = parse_one(:simple_str)

      def parse_str_start
        val = @parse.current_token.value
        @parse.consume(:str_start)
        Aua.logger.debug("Primitives#parse_str_start") do
          "Starting string parsing with value: #{val.inspect}"
        end
        nil
      end

      def parse_str_part
        @str_parts ||= [] # : Array[AST::Node]
        value = @parse.current_token.value
        @parse.consume(:str_part)
        part = s(:str_part, value)
        @str_parts << part

        nil
      end

      def parse_str_end
        @str_parts ||= [] # : Array[AST::Node]
        @parse.consume(:str_end)
        # If we have str_parts, we can return a structured string node
        return s(:str, @str_parts.first.value) if @str_parts.size == 1

        s(:structured_str, @str_parts)
      end

      def parse_parens
        @parse.consume(:lparen)
        expr = @parse.send :parse_expression
        begin
          @parse.consume(:rparen)
        rescue Aua::Error
          raise Error, "Unmatched opening parenthesis"
        end
        expr
      end

      def parse_generative_lit
        value = @parse.current_token.value
        @parse.consume(:gen_lit)
        s(:structured_gen_lit, [s(:str, value)])
      end

      private

      def parse_one(type)
        value = @parse.current_token.value
        @parse.consume(type)
        s(type, value)
      end
    end
  end
end
