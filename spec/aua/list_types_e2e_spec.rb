# frozen_string_literal: true

require "spec_helper"

RSpec.describe "List Types End-to-End" do
  describe "basic list support" do
    it "can declare and use list types without generics" do
      code = <<~AUA
        type ItemList = List
        items = ItemList
        items
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("ItemList")
    end

    it "can parse record types with list fields" do
      code = <<~AUA
        type Inventory = {
          items: List,
          capacity: Int
        }
        Inventory
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("Inventory")
    end

    it "can create objects with list fields" do
      code = <<~AUA
        type Player = {
          name: Str,
          items: List
        }

        player_data = {
          name: "Alice",
          items: ["sword", "potion"]
        }

        player = player_data as Player
        player.name
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to eq("Alice")
    end
  end

  describe "generic list support (future)" do
    xit "can declare parameterized list types" do
      code = <<~AUA
        type StringList = List<Str>
        type ItemList = List<Item>
      AUA

      # This should work in the future
      expect { Aua.run(code) }.not_to raise_error
    end

    xit "can use generic lists in record types" do
      code = <<~AUA
        type Inventory = {
          items: List<Str>,
          weapons: List<Weapon>
        }
      AUA

      expect { Aua.run(code) }.not_to raise_error
    end
  end

  describe "list casting and manipulation" do
    it "can cast array literals to list types", :llm_required do
      code = <<~AUA
        type Equipment = {
          weapons: List,
          armor: List
        }

        gear = {
          weapons: ["sword", "bow"],
          armor: ["helmet", "chainmail"]
        }

        equipment = gear as Equipment
        equipment.weapons
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::List)
      expect(result.values).to all(be_a(Aua::Str))
    end
  end

  describe "adventure game integration" do
    it "can parse the adventure game type definitions" do
      # This is the actual failing case from bin/adventure
      code = <<~AUA
        type Stats = {
          health: Int,
          strength: Int,
          intelligence: Int,
          charisma: Int
        }

        type Inventory = {
          items: List,
          gold: Int,
          capacity: Int
        }

        type Location = {
          name: Str,
          description: Str,
          exits: List,
          items: List,
          npcs: List
        }

        type Player = {
          name: Str,
          profession: Str,
          stats: Stats,
          inventory: Inventory,
          current_location: Str,
          level: Int
        }

        Player
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Klass)
      expect(result.name).to eq("Player")
    end
  end
end
