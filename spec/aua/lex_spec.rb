# frozen_string_literal: true

require 'spec_helper'
require 'aua/lex'

module Aua
  RSpec.describe Lex do
        let(:lexer) { described_class.new(input) }
        let(:tokens) { lexer.tokens.to_a }
    describe 'gen-string literal' do
      let(:input) { "\"\"\"The current day is #{Time.now.strftime("%A")}. Please come up with a rhyming couplet that describes the day of the week. If you can try to be alliterative, starting as many words as you can with the first two characters of the day name.\"\"\"" }
      it 'captures the full string, including the first two characters' do

        # Find the string token (adjust type as needed)
        str_token = tokens.find { |t| t.type == :gen_lit }
        expect(str_token).not_to be_nil
        expect(str_token.value).to start_with('The current day is ')
        expect(str_token.value).to match Time.now.strftime("%A")
        expect(str_token.value).to end_with('day name.')
        expect(str_token.value.length).to be >= 2
      end
    end
  end
end
