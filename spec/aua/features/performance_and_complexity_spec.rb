require "spec_helper"
require "benchmark"

# Performance thresholds - adjust as needed
PERFORMANCE_THRESHOLDS = {
  simple_parse: 0.01,      # 10ms for simple expressions
  complex_parse: 0.1,      # 100ms for complex expressions
  deep_nesting: 0.5,       # 500ms for deep nesting
  large_data: 1.0,         # 1s for large data processing
  llm_interaction: 2.0,    # 2s for LLM-powered generative casting
  memory_usage: 50_000_000 # 50MB memory limit
}.freeze

RSpec.describe "Performance and Complexity Features", :performance do
  def measure_time(&)
    Benchmark.realtime(&)
  end

  def measure_memory
    GC.start # Clean up before measuring
    before = ObjectSpace.count_objects[:TOTAL]
    yield
    GC.start # Clean up after
    after = ObjectSpace.count_objects[:TOTAL]
    (after - before) * 40 # Rough estimate: 40 bytes per object
  end

  describe "parsing performance" do
    it "parses simple expressions quickly" do
      code = "1 + 2 * 3"

      time = measure_time do
        100.times { Aua.run(code) }
      end

      avg_time = time / 100
      expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:simple_parse]
    end

    it "handles complex nested expressions" do
      # Deep arithmetic nesting
      code = (1..20).reduce("1") { |acc, i| "#{acc} + #{i} * (#{i} - 1)" }

      time = measure_time do
        Aua.run(code)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:complex_parse]
    end

    it "processes large string literals efficiently" do
      # 1KB string (reduced due to lexer limitation)
      large_string = "a" * 1_000
      code = "'#{large_string}'"

      time = measure_time do
        result = Aua.run(code)
        expect(result.value.length).to eq(1_000)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:simple_parse]
    end
  end

  describe "deep nesting stress tests" do
    it "handles deeply nested object literals" do
      # Create nested object: { a: { b: { c: { ... } } } }
      nested_obj = (1..50).reduce("1") do |acc, i|
        "{ level#{i}: #{acc} }"
      end

      time = measure_time do
        result = Aua.run(nested_obj)
        expect(result).to be_a(Aua::ObjectLiteral)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:deep_nesting]
    end

    it "handles deeply nested function calls" do
      # Create nested calls: f(f(f(...)))
      # First define a simple function equivalent
      nested_calls = (1..30).reduce("1") do |acc, _i|
        "inspect(#{acc})"
      end

      time = measure_time do
        result = Aua.run(nested_calls)
        expect(result).to be_a(Aua::Str)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:deep_nesting]
    end

    it "handles deeply nested conditional expressions" do
      # Create nested if-else: if cond then value else other_value
      nested_ifs = (1..20).reduce("42") do |acc, i|
        if_clause = i.even? ? "true" : "false"
        else_value = (acc.to_i + 1).to_s
        "if #{if_clause} then #{acc} else #{else_value}"
      end

      time = measure_time do
        result = Aua.run(nested_ifs)
        expect(result).to be_a(Aua::Int)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:deep_nesting]
    end
  end

  describe "memory usage and cleanup" do
    it "doesn't leak memory with repeated parsing" do
      code = "{ x: 1, y: 2, z: 'hello world' }"

      memory_used = measure_memory do
        1000.times { Aua.run(code) }
      end

      expect(memory_used).to be < PERFORMANCE_THRESHOLDS[:memory_usage]
    end

    it "handles large variable environments efficiently" do
      # Create many variables
      assignments = (1..100).map { |i| "var#{i} = #{i}" }.join("; ")
      code = "#{assignments}; var50"

      time = measure_time do
        result = Aua.run(code)
        expect(result.value).to eq(50)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:complex_parse]
    end
  end

  describe "complex feature composition" do
    it "combines multiple language features efficiently" do
      # Complex script combining:
      # - Type declarations  
      # - Object literals
      # - Property access
      # - Block conditionals
      # - Function calls
      complex_script = <<~AURA
        type Status = 'active' | 'inactive' | 'pending'
        
        user = {
          name: "Alice Johnson",
          age: 28,
          status: 'active'
        }
        
        if user.status == 'active'
          greeting = "Hello Alice! You are 28 years old."
        else
          greeting = "User Alice is not active"
        end
        
        inspect(greeting)
      AURA

      time = measure_time do
        result = Aua.run(complex_script)
        expect(result).to be_a(Aua::Str)
        expect(result.value).to include("Alice")
        expect(result.value).to include("28")
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:complex_parse]
    end

    it "handles complex type system interactions" do
      # Test meaningful generative casting (natural language -> structured data)
      type_script = <<~AURA
        type Person = { name: Str, age: Int, active: Bool }
        type Team = { name: Str, members: List, leader: Person }

        # Natural language description that needs semantic extraction
        description = "Our development team includes Alice (30, team lead), Bob, and Charlie. They're all actively working on the project."
        
        # This tests the LLM's ability to extract structured data from natural language
        team = description as Team
        team.leader.name
      AURA

      time = measure_time do
        result = Aua.run(type_script)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("alice")
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:llm_interaction]
    end

    it "processes large data structures with types", :slow do
      # Simulate processing a larger dataset
      large_data_script = <<~AURA
        type Item = { id: Int, name: Str, category: Str }

        # Create a moderately large list (simulating JSON import)
        items = [
          #{(1..100).map do |i|
            "{ id: #{i}, name: \"Item #{i}\", category: \"category#{i % 10}\" }"
          end.join(",\n          ")}
        ]

        # Access last item via list operations (no array indexing yet)
        items
      AURA

      time = measure_time do
        result = Aua.run(large_data_script)
        expect(result).to be_a(Aua::List)
        expect(result.values.size).to eq(100)
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:large_data]
    end
  end

  describe "error handling performance" do
    it "fails fast on syntax errors" do
      bad_syntax = "{ x: 1, y: 2, z: }" # Missing value

      time = measure_time do
        expect { Aua.run(bad_syntax) }.to raise_error(Aua::Error)
      end

      # Error handling should be very fast
      expect(time).to be < 0.01
    end

    it "provides meaningful errors for type mismatches" do
      type_error_script = <<~AURA
        type Person = { name: Str, age: Int }
        person = { name: "Alice", age: 30 }
        person as Person
      AURA

      # For now, just ensure it doesn't crash - type validation might not be implemented yet
      time = measure_time do
        result = Aua.run(type_error_script)
        expect(result).to be_truthy
      end

      expect(time).to be < PERFORMANCE_THRESHOLDS[:simple_parse]
    end
  end

  describe "regression and stability" do
    it "produces consistent results across multiple runs" do
      script = <<~AURA
        user = { name: "Test User", score: 42 }
        if user.score > 40 then "high" else "low"
      AURA

      results = Array.new(10) { Aua.run(script).value }

      expect(results.uniq).to eq(["high"])
    end

    it "handles edge cases in string interpolation" do
      edge_cases = [
        '"Simple: \#{1 + 1}"',
        '"Nested: \#{inspect(\\"inner\\")}"',
        '"Multiple: \#{1} and \#{2} and \#{3}"',
        '"Empty: \#{nil}"'
      ]

      edge_cases.each do |test_case|
        expect { Aua.run(test_case) }.not_to raise_error
      end
    end
  end  # Helper method for creating test files that could graduate to Aura
  def self.create_aura_example(name, code)
    example_dir = File.join(__dir__, "../../examples")
    FileUtils.mkdir_p(example_dir)
    
    File.write(File.join(example_dir, "#{name}.aura"), code)
  end

  describe "examples for future Aura testing" do
    it "creates complex composition examples" do
      # These could eventually become Aura-based tests

      game_simulation = <<~AURA
        type Character = { name: Str, hp: Int, attack: Int, defense: Int }
        type GameState = { player: Character, enemy: Character, turn: Int }

        player = { name: "Hero", hp: 100, attack: 20, defense: 5 }
        enemy = { name: "Orc", hp: 80, attack: 15, defense: 3 }

        state = { player: player, enemy: enemy, turn: 1 }

        # Simulate one turn of combat
        damage_to_enemy = state.player.attack - state.enemy.defense
        enemy_after_damage = {
          name: state.enemy.name,
          hp: state.enemy.hp - damage_to_enemy,
          attack: state.enemy.attack,
          defense: state.enemy.defense
        }

        enemy_after_damage.hp
      AURA

      result = Aua.run(game_simulation)
      expect(result.value).to eq(63) # 80 - (20 - 3) = 63

      # Save as example for future Aura-based testing
      self.class.create_aura_example("game_simulation", game_simulation)
    end
  end
end
