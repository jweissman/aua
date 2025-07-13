# frozen_string_literal: true

require "spec_helper"
require "aua"

RSpec.describe "End-to-End Type System Features" do
  describe "Array member indexing with typed lists" do
    it "can access typed list elements with proper type inference" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>

        people = [
          { name: "Alice", age: 30 },
          { name: "Bob", age: 25 }
        ] : PersonList

        first_person = people[0]
        first_person.name
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice")
    end

    it "can access nested fields in typed lists" do
      code = <<~AURA
        type Address = { street: String, city: String }
        type Person = { name: String, address: Address }
        type PersonList = List<Person>

        people = [
          {#{" "}
            name: "Charlie",#{" "}
            address: { street: "123 Main St", city: "Portland" }
          }
        ] : PersonList

        people[0].address.city
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Portland")
    end

    it "can work with List<String> indexing" do
      code = <<~AURA
        type StringList = List<String>

        names = ["Alice", "Bob", "Charlie"] : StringList
        names[1]
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Bob")
    end
  end

  describe "For loops over typed collections" do
    it "can iterate over str list" do
      code = <<~AURA
        type StringList = List<String>

        names = ["Alice", "Bob"] : StringList
        result = ""

        for name in names do
          result = result + name + " "
        end

        result
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice Bob ")
    end

    it "can iterate over List<Person> and access fields" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>

        people = [
          { name: "Alice", age: 30 },
          { name: "Bob", age: 25 }
        ] : PersonList

        total_age = 0

        for person in people do
          total_age = total_age + person.age
        end

        total_age
      AURA

      result = Aua.run(code)
      expect(result.value).to eq(55)
    end

    it "can build new collections while iterating" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>
        type StringList = List<String>

        people = [
          { name: "Alice", age: 30 },
          { name: "Bob", age: 25 }
        ] : PersonList

        names = [] : StringList

        for person in people do
          names = names + [person.name]
        end

        names[0]
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice")
    end
  end

  describe "Nested generic structures" do
    it "can handle List<Dict<String, Int>>" do
      code = <<~AURA
        type ScoreMap = Dict<String, Int>
        type ScoreList = List<ScoreMap>

        game_scores = [
          { "Alice": 100, "Bob": 85 },
          { "Charlie": 95, "Dave": 88 }
        ] : ScoreList

        game_scores[0]["Alice"]
      AURA

      result = Aua.run(code)
      expect(result.value).to eq(100)
    end

    it "can handle Dict<String, List<String>>" do
      code = <<~AURA
        type StringList = List<String>
        type CategoryMap = Dict<String, StringList>

        categories = {
          "fruits": ["apple", "banana"],
          "colors": ["red", "blue"]
        } : CategoryMap

        categories["fruits"][0]
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("apple")
    end

    it "can handle complex nested structures" do
      code = <<~AURA
        type Task = { title: String, done: Bool }
        type TaskList = List<Task>
        type Project = { name: String, tasks: TaskList }
        type ProjectList = List<Project>

        projects = [
          {
            name: "Website",
            tasks: [
              { title: "Design mockup", done: true },
              { title: "Implement frontend", done: false }
            ]
          }
        ] : ProjectList

        projects[0].tasks[0].title
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Design mockup")
    end
  end

  describe "User-defined generic types", :skip do
    it "can create custom Maybe<T> type" do
      code = <<~AURA
        type Maybe<T> = T | Nihil
        type MaybeString = Maybe<String>

        value = "hello" : MaybeString
        typeof value
      AURA

      result = Aua.run(code)
      # For now, we expect the union type representation
      expect(result.value).to match(/String|MaybeString/)
    end

    it "can create custom Pair<A, B> type" do
      code = <<~AURA
        type Pair<A, B> = { first: A, second: B }
        type StringIntPair = Pair<String, Int>

        pair = { first: "answer", second: 42 } : StringIntPair
        pair.first + " is " + pair.second
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("answer is 42")
    end

    it "can nest user-defined generics" do
      code = <<~AURA
        type Container<T> = { value: T }
        type StringContainer = Container<String>
        type ContainerList = List<StringContainer>

        containers = [
          { value: "first" },
          { value: "second" }
        ] : ContainerList

        containers[1].value
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("second")
    end
  end

  describe "Function parameters with generic types", :skip do
    it "can define functions that work with typed lists" do
      code = <<~AURA
        type StringList = List<String>

        fun get_first(items)
          items[0]
        end

        names = ["Alice", "Bob"] : StringList
        get_first(names)
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice")
    end

    it "can define functions that work with custom types" do
      code = <<~AURA
        type Person = { name: String, age: Int }

        fun greet(person)
          "Hello, " + person.name + "!"
        end

        alice = { name: "Alice", age: 30 } : Person
        greet(alice)
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Hello, Alice!")
    end

    it "can define functions that return typed values" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>

        fun create_person(name, age)
          { name: name, age: age }
        end

        fun create_team()
          [
            create_person("Alice", 30),
            create_person("Bob", 25)
          ]
        end

        team = create_team()
        team[0].name
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice")
    end
  end

  describe "Type-safe data transformations" do
    it "can transform data while preserving types" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>

        fun add_year(person)
          { name: person.name, age: person.age + 1 }
        end

        people = [
          { name: "Alice", age: 30 }
        ] : PersonList

        older_person = add_year(people[0])
        older_person.age
      AURA

      result = Aua.run(code)
      expect(result.value).to eq(31)
    end

    it "can filter and map over typed collections" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>
        type StringList = List<String>

        people = [
          { name: "Alice", age: 30 },
          { name: "Bob", age: 17 },
          { name: "Charlie", age: 25 }
        ] : PersonList

        adult_names = [] : StringList

        for person in people do
          if person.age >= 18
            adult_names = adult_names + [person.name]
          end
        end

        adult_names[0]
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Alice")
    end
  end

  describe "LLM integration with complex types" do
    it "can generate data for nested structures" do
      code = <<~AURA
        type Task = { title: String, priority: Int }
        type TaskList = List<Task>
        type Project = { name: String, tasks: TaskList }

        project = "Create a simple web project with 2 tasks" as Project
        typeof project
      AURA

      result = Aua.run(code)
      expect(result.value).to eq("Project")
    end

    it "can generate typed lists with specific constraints" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        type PersonList = List<Person>

        team = "Generate 3 team members for a startup" as PersonList
        typeof team
      AURA

      result = Aua.run(code)
      expect(result.value).to match(/PersonList|List/)
    end

    it "can work with user-defined generic types", :skip do
      code = <<~AURA
        type Container<T> = { value: T, metadata: String }
        type StringContainer = Container<String>

        container = "A container holding a greeting message" as StringContainer
        typeof container
      AURA

      result = Aua.run(code)
      expect(result.value).to match(/StringContainer|Container/)
    end
  end

  describe "Error handling and type safety" do
    it "should provide meaningful errors for type mismatches" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        person = { name: "Alice", age: "thirty" } : Person
      AURA

      expect { Aua.run(code) }.to raise_error(/type/i)
    end

    it "should handle missing fields gracefully" do
      code = <<~AURA
        type Person = { name: String, age: Int }
        person = { name: "Alice" } : Person
      AURA

      expect { Aua.run(code) }.to raise_error(/field|age/i)
    end

    it "should validate array bounds" do
      code = <<~AURA
        type StringList = List<String>
        names = ["Alice"] : StringList
        names[5]
      AURA

      expect { Aua.run(code) }.to raise_error(/index|bound/i)
    end
  end

  describe "Real-world scenario: Game character management" do
    it "can model a complete game character system" do
      code = <<~AURA
        type Stat = { name: String, value: Int }
        type StatList = List<Stat>
        type Skill = { name: String, level: Int }
        type SkillList = List<Skill>
        type Character = {
          name: String,
          level: Int,
          stats: StatList,
          skills: SkillList
        }
        type Party = List<Character>

        fun create_stat(name, value)
          { name: name, value: value }
        end

        fun create_character(name)
          {
            name: name,
            level: 1,
            stats: [
              create_stat("Strength", 10),
              create_stat("Dexterity", 12)
            ],
            skills: [
              { name: "Swordsmanship", level: 1 }
            ]
          }
        end

        hero = create_character("Aragorn")
        hero.stats[0].value
      AURA

      result = Aua.run(code)
      expect(result.value).to eq(10)
    end

    it "can perform complex operations on the character system", :skip do
      code = <<~AURA
        type Character = { name: String, level: Int, health: Int }
        type Party = List<Character>

        party = [
          { name: "Fighter", level: 5, health: 100 },
          { name: "Mage", level: 4, health: 60 },
          { name: "Rogue", level: 6, health: 80 }
        ] : Party

        total_health = 0
        highest_level = 0

        for character in party do
          total_health = total_health + character.health
          if character.level > highest_level then
            highest_level = character.level
          end
        end

        # Return party size, total health, and highest level
        [party.length, total_health, highest_level]
      AURA

      result = Aua.run(code)
      expect(result.value).to be_a(Aua::List)
      expect(result.values.map(&:value)).to eq([3, 240, 6])
    end
  end

  describe "semantic equality" do
    it "handles fuzzy similarity for complex types" do
      expect("\"house\" ~= \"home\"").to be_aua(true).and_be_a(Aua::Bool)
      expect("\"ok\" ~= \"okay\"").to be_aua(true).and_be_a(Aua::Bool)
      expect("\"hello\" ~= \"greetings\"").to be_aua(true).and_be_a(Aua::Bool)
      expect("\"yes\" ~= \"affirmative\"").to be_aua(true).and_be_a(Aua::Bool)

      expect("\"hello\" ~= \"goodbye\"").to be_aua(false).and_be_a(Aua::Bool)
      expect("\"blue\" ~= \"red\"").to be_aua(false).and_be_a(Aua::Bool)
      expect("\"cat\" ~= \"dog\"").to be_aua(false).and_be_a(Aua::Bool)
      expect("\"apple\" ~= \"banana\"").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  describe "edge cases", :skip do
    it "empty fns" do
      code = <<~AURA
        fun empty_function() : Int
          0

        empty_function()
      AURA

      result = Aua.run(code)
      expect(result.value).to eq(0)
    end
  end
end
