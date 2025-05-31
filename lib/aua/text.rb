module Aua
  # Provides utility methods for text processing, such as indicating a position in code.
  module Text
    # Represents a cursor in the source code, tracking the current column and line.
    class Cursor
      attr_reader :column, :line

      def initialize(col, line)
        @column = col
        @line = line
      end

      def advance = @column += 1
      def newline = @line += 1
    end

    # Represents a document containing source code, with methods to navigate and manipulate it.
    class Document
      attr_reader :cursor, :position

      def initialize(text)
        @text = text
        @cursor = Cursor.new(1, 1)
        @position = 0
      end

      def peek = @text.chars.fetch(@position, nil)
      def finished? = @position >= @text.length
      def slice(start, length) = @text.slice(start, length)

      # Advances the lexer by one character, updating position and line/column counters.
      def advance
        @position += 1
        @cursor.advance
        return unless peek == "\n"

        @cursor.newline
      end

      def indicate = Text.indicate(@text, @cursor)
    end

    # Indicates the position of a character in the code by printing the line
    # and an indicator pointing to the character's position.
    #
    # @param code [String] The code to indicate within.
    # @param column [Integer] The column number to point to (1-based).
    # @param line [Integer, nil] The line number to point to (1-based), or nil for all lines.
    # @return [Array<String>] The lines with an indicator.
    def self.indicate(text, cursor)
      lines = text.lines
      line = cursor.line
      column = cursor.column
      lines.each_with_index.map do |line_content, index|
        if line.nil? || index + 1 == line
          "#{line_content.chomp}\n#{" " * (column - 1)}^"
        else
          line_content.chomp
        end
      end
    end
  end
end
