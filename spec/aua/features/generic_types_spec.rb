# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "Generic Types" do
  context "List<T> generic syntax" do
    it "can declare a typed list with List<String>" do
      code = <<~AURA
        type BookList = List<String>
        books = [] : BookList
        typeof books
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end

    it "can declare a typed list with Dict<String, Int>" do
      code = <<~AURA
        type ScoreList = Dict<String, Int>
        scores = {} : ScoreList
        typeof scores
      AURA
      expect(code).to be_aua("Dict<String, Int>").and_be_a(Aua::Str)
    end

    it "can cast arrays to typed lists" do
      code = <<~AURA
        numbers = [1, 2, 3] as List<String>
        typeof numbers
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end

    it "can declare a struct with a List field" do
      code = <<~AURA
        type Library = {
          name: String,
          books: List<String>
        }

        lib = {
          name: "Central Library",
          books: ["Dune", "Silmarillion", "Chainmail Manual"]
        } : Library

        typeof(lib.books)
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end

    it "can declare a list with an arbitrary type" do
      code = <<~AURA
        type ItemList = List<{ name: String, price: Float }>
        items = [
          { name: "Apple", price: 0.5 },
          { name: "Banana", price: 0.3 }
        ] : ItemList
        typeof items
      AURA
      expect(code).to be_aua("List<{ name => String, price => Float }>").and_be_a(Aua::Str)
    end
  end

  context "LLM integration with typed lists" do
    it "can generate structured data for List<String>" do
      code = <<~AURA
        type TaskList = List<String>
        tasks = """Generate 3 simple daily tasks""" as TaskList
        typeof tasks
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end

    it "can generate structured data for complex object lists" do
      code = <<~AURA
        type PersonList = List<{ name: String, age: Int }>
        people = "Generate 2 fictional characters" as PersonList
        typeof people
      AURA
      expect(code).to be_aua("List<{ name => String, age => Int }>").and_be_a(Aua::Str)
    end
  end

  context "generic struct with List field" do
    it "can create a struct with a List<String> field" do
      code = <<~AURA
        type Library = {
          name: String,
          books: List<String>
        }

        lib = "Dune, Silmarillion and Chainmail Manual" as Library

        typeof(lib.books)
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end

    it "can generate a struct with List field using LLM" do
      code = <<~AURA
        type GameCharacter = {
          name: String,
          abilities: List<String>,
          level: Int
        }

        hero = """Create a fantasy RPG character""" as GameCharacter
        typeof(hero.abilities)
      AURA
      expect(code).to be_aua("List<String>").and_be_a(Aua::Str)
    end
  end
end
