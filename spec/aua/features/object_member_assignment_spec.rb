# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Object Member Assignment Features" do
  describe "functional member assignment" do
    it "assigns to object member and returns new object" do
      code = <<~AUA
        type Person = { name: String, age: Int }

        person = { name: "Alice", age: 30 }
        person.age = 31

        person.age
      AUA

      expect(code).to be_aua(31).and_be_a(Aua::Int) # Mutation
    end

    it "returns the new object with updated field" do
      code = <<~AUA
        type Person = { name: String, age: Int }

        person = { name: "Alice", age: 30 }
        updated_person = person.dup()
        updated_person.age = 31
        person.age
      AUA

      expect(code).to be_aua(30) # New object has updated value
    end

    it "preserves other fields when updating one field" do
      code = <<~AUA
        type Person = { name: String, age: Int }

        person = { name: "Alice", age: 30 }
        person.age = 31

        person.name
      AUA

      expect(code).to be_aua("Alice") # Other fields preserved
    end

    it "works with nested object assignment" do
      code = <<~AUA
        type Address = { street: Str, city: Str }
        type Person = { name: Str, address: Address }

        person = {
          name: "Alice",
          address: { street: "123 Main St", city: "Boston" }
        }
        person.address = { street: "456 Oak Ave", city: "Boston" }

        person.address.street
      AUA

      expect(code).to be_aua("456 Oak Ave")
    end
  end

  describe "error handling" do
    it "raises error when trying to assign to non-existent field" do
      code = <<~AUA
        type Person = { name: Str, age: Int }

        person = { name: "Alice", age: 30 }
        person.invalid_field = "value"
      AUA

      # expect { run_aura(code) }.to raise_error(/field.*invalid_field.*not.*found/i)
      expect(code).to raise_aura(/invalid_field.*not.*found/)
    end

    it "raises error when trying to assign incompatible type", :skip do
      code = <<~AUA
        type Person = { name: Str, age: Int }

        person = { name: "Alice", age: 30 }
        person.age = "not a number"
      AUA

      expect(code).to raise_aura(/type.*mismatch/i)
    end
  end
end
