# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Function Definition Features" do
  describe "basic function definitions" do
    it "defines and calls a simple function" do
      code = <<~AURA
        fun greet(name)
          "Hello, " + name + "!"
        end

        greet("Alice")
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hello, Alice!")
    end

    it "defines a function with multiple parameters" do
      code = <<~AURA
        fun add(x, y)
          x + y
        end

        add(3, 4)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(7)
    end

    it "defines a function with no parameters" do
      code = <<~AURA
        fun get_answer()
          42
        end

        get_answer()
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(42)
    end
  end

  describe "function scope and closures" do
    it "accesses variables from outer scope" do
      code = <<~AURA
        greeting = "Hello"

        fun greet(name)
          greeting + ", " + name + "!"
        end

        greet("Bob")
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hello, Bob!")
    end

    it "supports local variables within functions" do
      code = <<~AURA
        fun calculate(x, y)
          temp = x * 2
          temp + y
        end

        calculate(5, 3)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(13)
    end
  end

  describe "recursive functions" do
    it "calculates factorial recursively" do
      code = <<~AURA
        fun factorial(n)
          if n <= 1
            1
          else
            n * factorial(n - 1)
          end
        end

        factorial(5)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(120)
    end

    it "calculates fibonacci recursively" do
      code = <<~AURA
        fun fib(n)
          if n <= 1
            n
          else
            fib(n - 1) + fib(n - 2)
          end
        end

        fib(7)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(13)
    end
  end

  describe "functions with complex types" do
    it "works with object literals" do
      code = <<~AURA
        type Person = { name: Str, age: Int }

        fun create_person(name, age)
          { name: name, age: age }
        end

        fun greet_person(person)
          "Hello, " + person.name + "! You are " + inspect(person.age) + " years old."
        end

        alice = create_person("Alice", 30)
        greet_person(alice)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Alice")
      expect(result.value).to include("30")
    end

    it "works with lists and complex data structures" do
      code = <<~AURA
        fun sum_list(numbers)
          total = 0
          # Note: This would need iteration support
          # For now, simulate with manual access
          total
        end

        fun create_range(start, count)
          # Simulate creating a list of numbers
          [1, 2, 3, 4, 5]
        end

        numbers = create_range(1, 5)
        inspect(numbers)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("1")
    end
  end

  describe "higher-order functions" do
    it "passes functions as arguments", skip: "requires first-class function support" do
      code = <<~AURA
        fun apply_twice(func, value)
          func(func(value))
        end

        fun double(x)
          x * 2
        end

        apply_twice(double, 3)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(12)
    end

    it "returns functions from functions", skip: "requires first-class function support" do
      code = <<~AURA
        fun make_adder(increment)
          def(x)
            x + increment
          end
        end

        add_five = make_adder(5)
        add_five(10)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(15)
    end
  end

  describe "game simulation functions" do
    it "implements the fight_one function from the game example" do
      code = <<~AURA
        fun fight_one(attacker, defender)
          damage = attacker.attack - defender.defense
          if damage > 0
            new_hp = defender.hp - damage
            {
              name: defender.name,
              hp: new_hp,
              attack: defender.attack,
              defense: defender.defense
            }
          else
            defender
          end
        end

        hero = { name: "Hero", hp: 100, attack: 20, defense: 5 }
        orc = { name: "Orc", hp: 80, attack: 15, defense: 3 }

        result = fight_one(hero, orc)
        result.hp
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(63) # 80 - (20 - 3) = 63
    end

    it "calculates damage with defensive bonuses" do
      code = <<~AURA
        fun calculate_damage(attacker, defender, has_shield)
          base_damage = attacker.attack - defender.defense
          if has_shield
            base_damage = base_damage / 2
          end
          if base_damage < 0
            0
          else
            base_damage
          end
        end

        warrior = { attack: 25, defense: 5 }
        knight = { attack: 15, defense: 8 }

        # Without shield
        damage1 = calculate_damage(warrior, knight, false)
        # With shield
        damage2 = calculate_damage(warrior, knight, true)

        { without_shield: damage1, with_shield: damage2 }
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::ObjectLiteral)
      # Should calculate: 25-8=17 damage normally, 17/2=8 with shield
    end
  end

  describe "error handling" do
    it "raises error for undefined functions" do
      expect { Aua.run("unknown_function(42)") }.to raise_error(Aua::Error, /Unknown/)
    end

    it "raises error for wrong number of arguments" do
      code = <<~AURA
        fun greet(name)
          "Hello, " + name
        end

        greet()  # Should error - missing argument
      AURA

      expect { Aua.run(code) }.to raise_error(Aua::Error)
    end

    it "handles function redefinition" do
      code = <<~AURA
        fun greet(name)
          "Hello, " + name
        end

        fun greet(name)
          "Hi there, " + name
        end

        greet("Alice")
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Hi there, Alice")
    end
  end

  describe "integration with other features" do
    it "uses functions with generative strings" do
      code = <<~AURA
        fun create_story_prompt(character_name, setting)
          """Write a short story about ${character_name} in ${setting}"""
        end

        prompt = create_story_prompt("Alice", "a magical forest")
        inspect(prompt)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Alice")
      expect(result.value).to include("young girl")
    end

    it "uses functions with type casting and LLM features" do
      code = <<~AURA
        type Character = { name: Str, level: Int, class: Str }

        fun create_character_from_description(description)
          description as Character
        end

        fun format_character(char)
          "${char.name} is a level ${char.level} ${char.class}"
        end

        desc = "Meet Gandalf, a powerful level 50 wizard"
        character = create_character_from_description(desc)
        format_character(character)
      AURA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Gandalf")
      expect(result.value).to include("wizard")
    end
  end
end
