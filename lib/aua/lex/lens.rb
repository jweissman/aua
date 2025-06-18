module Aua
  # A lexer for the Aua language.
  # Responsible for converting source code into a stream of tokens.
  class Lex
    # Provides a lens for inspecting the current position in the source code.
    class Lens
      def initialize(doc)
        @doc = doc
      end

      def eof? = @doc.finished?
      def more? = !eof?
      def peek = @doc.peek
      def peek_n(inc) = @doc.peek_n(inc)

      # Current position and character information
      def current_pos = @doc.position || 0
      def current_line = @doc.cursor.line
      def current_column = @doc.cursor.column
      def current_char = @doc.current || ""

      def describe = "#{current_line}:#{current_column} #{describe_character(current_char)}"

      def describe_character(char)
        case char
        when ";" then "semicolon"
        else "character #{char.inspect}"
        end
      end

      def identify(message: nil, hint: nil)
        <<~ERROR
          #{message} at line #{current_line}, column #{current_column}:

          #{@doc.indicate}
          #{hint || describe_character(current_char)}
        ERROR
      end
    end
  end
end
