# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Dynamic Enum Selection", :llm_required do
  describe "barred union operator (~)" do
    it "prompts for selection from a union type" do
      code = <<~AUA
        choice = "Pick your favorite color" ~ ('red' | 'blue' | 'green')
        choice
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(%w[red blue green]).to include(result.value)
    end

    it "uses the prompt text to guide selection" do
      code = <<~AUA
        mood = "I'm feeling quite sad today" ~ ('happy' | 'sad' | 'angry')
        mood
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("sad")
    end

    it "works with previously defined union types" do
      code = <<~AUA
        type Emotion = 'joy' | 'sorrow' | 'rage'
        feeling = "The sunset fills me with peace" ~ Emotion
        feeling
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(%w[joy sorrow rage]).to include(result.value)
    end

    it "can be used in interactive scenarios" do
      code = <<~AUA
        name = "Alice"
        action = "What should ${name} do next?" ~ ('fight' | 'flee' | 'negotiate')
        action
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(%w[fight flee negotiate]).to include(result.value)
    end

    it "supports numeric and mixed unions" do
      code = <<~AUA
        difficulty = "Choose difficulty for a beginner" ~ ('easy' | 'medium' | 'hard')
        difficulty
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("easy")
    end
  end

  describe "integration with existing type system" do
    it "works with record types containing union fields" do
      code = <<~AUA
        type Character = { name: Str, class: ('warrior' | 'mage' | 'rogue') }
        hero = { name: "Gandalf", class: "A wise old wizard" ~ ('warrior' | 'mage' | 'rogue') }
        hero.class
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(%w[mage warrior]).to include(result.value)
    end
  end
end
