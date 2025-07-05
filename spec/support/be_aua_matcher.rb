# frozen_string_literal: true

# Custom RSpec matcher for testing Aua code execution
RSpec::Matchers.define :be_aua do |expected_value|
  match do |code|
    @result = Aua.run(code)

    if @expected_type && !@result.is_a?(@expected_type)
      # Check if the result is of the expected type
      raise "Expected type #{@expected_type}, but got #{@result.class}"
    end

    @result.value == expected_value
  end

  failure_message do
    "expected Aua code #{actual.inspect} to return #{expected_value.inspect}, but got #{@result.value.inspect}"
  end

  failure_message_when_negated do
    "expected Aua code #{actual.inspect} not to return #{expected_value.inspect}, but it did"
  end

  description do
    "run Aua code and return #{expected_value.inspect}"
  end

  # Allow chaining with type expectations
  chain :and_be_a do |expected_type|
    @expected_type = expected_type
  end

  private

  attr_reader :code, :result, :expected_type
end

RSpec::Matchers.define :raise_aura do |expected_value|
  match do |code|
    @error = nil
    Aua.run(code)
    false # If no error is raised, the match fails
  rescue Aua::Error => e
    @error = e
    @error.message == expected_value || (expected_value.is_a?(Regexp) && expected_value.match?(@error.message))
  end

  failure_message do
    "expected Aua code to raise an error with message '#{expected_value}', but #{@error&.message || "no error raised"}"
  end

  description do
    "raise an Aua error with message '#{expected_value}'"
  end
end
