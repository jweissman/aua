module Aua
  # IDEA: Enhanced error class that provides better context and position information
  # class ContextError < Error
  #   attr_reader :position, :context_lines, :message_detail

  #   def initialize(message, token: nil, context: nil)
  #     @message_detail = message
  #     @position = token&.at
  #     @context_lines = extract_context(context, @position) if context && @position

  #     super(build_error_message)
  #   end

  #   private

  #   def build_error_message
  #     parts = [@message_detail]

  #     parts << "at line #{@position.line}, column #{@position.column}" if @position

  #     if @context_lines&.any?
  #       parts << ""
  #       parts.concat(@context_lines)
  #     end

  #     parts.join("\n")
  #   end

  #   def extract_context(source_text, position)
  #     return nil unless position && source_text

  #     lines = source_text.lines
  #     target_line = position.line

  #     # Show the problematic line with a caret indicator
  #     if target_line <= lines.length
  #       line_content = lines[target_line - 1].chomp
  #       caret_line = (" " * [position.column - 1, 0].max) + "^"

  #       [line_content, caret_line]
  #     else
  #       ["(line #{target_line} not found in source)"]
  #     end
  #   end
  # end
end
