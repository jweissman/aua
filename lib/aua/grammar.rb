# Aua is a programming language and interpreter written in Ruby...
module Aua
  # Grammar helpers for constructing AST nodes.
  module Grammar
    PRIMARY_NAMES = {
      lparen: :parens,
      lbrace: :object_literal,
      lbracket: :array_literal,
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
      equals: 0, # assignment has lowest precedence
      lambda: 1, # lambda has very low precedence
      as: 2, # typecast has low precedence (looser than arithmetic, tighter than assignment)
      colon: 2, # type annotation has low precedence, similar to typecast
      tilde: 3, # enum selection has low precedence, similar to assignment
      or: 4, # logical OR has low precedence among operators
      and: 5, # logical AND has higher precedence than OR
      eq: 6, neq: 6, gt: 6, lt: 6, gte: 6, lte: 6, fuzzy_eq: 6, # comparison operators
      plus: 7, minus: 7,
      star: 8, slash: 8,
      pow: 9,
      dot: 10 # member access has high precedence
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
        # If we have no str_parts, this is an empty string
        return s(:str, "") if @str_parts.empty?
        # If we have str_parts, we can return a structured string node
        return s(:str, @str_parts.first.value) if @str_parts.size == 1

        s(:structured_str, @str_parts)
      end

      def parse_parens
        @parse.consume(:lparen)

        # Handle empty parentheses () - could be lambda params or empty tuple
        if @parse.current_token.type == :rparen
          @parse.consume(:rparen)
          return @parse.s(:unit)
        end

        # Try to parse as a potential parameter list first
        # Look for pattern: (id, id, ...) which could be lambda parameters
        first_expr = @parse.send :parse_expression

        # Check if we have a comma - if so, this is a parameter list
        if @parse.current_token.type == :comma
          # This is a comma-separated list, parse as tuple
          elements = [first_expr]

          while @parse.current_token.type == :comma
            @parse.consume(:comma)
            # Skip whitespace if needed
            @parse.advance while @parse.current_token.type == :eos
            elements << @parse.send(:parse_expression)
          end

          begin
            @parse.consume(:rparen)
          rescue Aua::Error
            @parse.send :parse_failure, "Unmatched opening parenthesis"
          end

          # Return a tuple node
          @parse.s(:tuple, elements)
        else
          # Single expression in parentheses
          begin
            @parse.consume(:rparen)
          rescue Aua::Error
            @parse.send :parse_failure, "Unmatched opening parenthesis"
          end
          first_expr
        end
      end

      def parse_generative_lit
        value = @parse.current_token.value
        @parse.consume(:gen_lit)
        s(:structured_gen_lit, [s(:str, value)])
      end

      def parse_object_literal
        @parse.consume(:lbrace)

        fields = [] # : Array[AST::Node]

        # Handle empty object
        return parse_empty_object if @parse.current_token.type == :rbrace

        # Parse fields
        loop do
          skip_whitespace
          field = parse_object_field
          fields << field
          skip_whitespace

          break unless continue_object_parsing?
        end

        @parse.consume(:rbrace)
        s(:object_literal, fields)
      end

      def parse_array_literal
        @parse.consume(:lbracket)

        elements = [] # : Array[AST::Node]

        # Handle empty array
        return parse_empty_array if @parse.current_token.type == :rbracket

        # Parse elements
        loop do
          skip_whitespace
          break if @parse.current_token.type == :rbracket

          element = @parse.send :parse_expression
          elements << element
          skip_whitespace

          break unless continue_array_parsing?
        end

        @parse.consume(:rbracket)
        s(:array_literal, elements)
      end

      private

      def parse_one(type)
        value = @parse.current_token.value
        @parse.consume(type)
        s(type, value)
      end

      def parse_empty_object
        @parse.consume(:rbrace)
        s(:object_literal, [])
      end

      def skip_whitespace
        @parse.advance while @parse.current_token.type == :eos
      end

      def parse_object_field
        case @parse.current_token.type
        when :id
          field_name = @parse.current_token.value
          @parse.consume(:id)
          @parse.consume(:colon)
          field_value = @parse.send :parse_expression
          s(:field, field_name, field_value)
        when :str_part
          # For string field names, we need to manually parse the string sequence
          field_name = parse_field_name_string
          @parse.consume(:colon)
          field_value = @parse.send :parse_expression
          s(:field, field_name, field_value)
        else
          raise Error, "Expected field name in object literal, got #{@parse.current_token.type}"
        end
      end

      def parse_field_name_string
        # Parse a string that's used as a field name in an object literal
        # This handles the str_part -> str_end sequence manually
        unless @parse.current_token.type == :str_part
          raise Error, "Expected string field name, got #{@parse.current_token.type}"
        end

        field_name = @parse.current_token.value
        @parse.consume(:str_part)

        # Consume the str_end token to complete the string
        unless @parse.current_token.type == :str_end
          raise Error, "Expected end of string field name, got #{@parse.current_token.type}"
        end

        @parse.consume(:str_end)

        field_name
      end

      def continue_object_parsing?
        case @parse.current_token.type
        when :comma
          @parse.consume(:comma)
          skip_whitespace
          true
        when :rbrace
          false
        else
          raise Error, "Expected ',' or '}' in object literal, got #{@parse.current_token.type}"
        end
      end

      def parse_empty_array
        @parse.consume(:rbracket)
        s(:array_literal, [])
      end

      def continue_array_parsing?
        case @parse.current_token.type
        when :comma
          @parse.consume(:comma)
          skip_whitespace
          true
        when :rbracket
          false
        else
          raise Error, "Expected ',' or ']' in array literal, got #{@parse.current_token.type}"
        end
      end
    end
  end
end
