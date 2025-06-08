# frozen_string_literal: true

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

      def to_s = "at line #{@line}, column #{@column}"
    end

    # Represents a document containing source code, with methods to navigate and manipulate it.
    class Document
      attr_reader :cursor, :position

      def initialize(text)
        @text = text
        @cursor = Cursor.new(1, 1)
        @position = 0
      end

      def current = @text.chars.fetch(@position, nil)
      def peek_at(index) = @text.chars.fetch(@position + index, nil)
      def peek = peek_at(1)

      def caret = @cursor.dup.freeze

      # Returns an array of the next n characters from the current position.
      # If there are fewer than n characters left, it returns as many as possible.
      # If n is 0, it returns an empty array.
      def peek_n(count) = 1.upto(count).map { |char| peek_at(char) || "" }
      def finished? = @position >= @text.length
      def slice(start, length) = @text.slice(start, length)

      # Advances the lexer by one character, updating position and line/column counters.
      def advance(inc = 1)
        count = inc.dup
        return if count.zero?

        while inc.positive? && !finished?
          inc -= 1
          @position += 1
          @cursor.advance
          next unless peek == "\n"

          @cursor.newline
        end
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
