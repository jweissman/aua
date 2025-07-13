# frozen_string_literal: true

require "spec_helper"

RSpec.describe "LLM Features", :llm do
  describe "generative string literals", gen: true do
    it "evaluates a generative string literal and returns a string containing Rayleigh" do
      result = Aua.run('"""What is the name of the physical phenomena responsible for the sky being blue?"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to match(/Rayleigh/i)
    end

    it "interpolates variables in generative strings" do
      result = Aua.run('name = "Alice"; """Please write a short story about ${name}"""')
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("Alice")
    end
  end

  describe "LLM-powered type casting", :llm_required do
    describe "structured data extraction" do
      it "extracts person data from natural language" do
        code = <<~AUA
          type Person = { name: Str, age: Int, city: Str }
          text = "Hi, I'm Sarah, I'm 28 years old and I live in Portland"
          person = text as Person
          person.name
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("sarah")
      end

      it "extracts contact information from email signatures" do
        code = <<~AUA
          type Contact = { name: Str, email: Str, phone: Str }
          signature = "Best regards, John Smith\\njohn.smith@example.com\\n(555) 123-4567"
          contact = signature as Contact
          contact.email
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("john.smith@example.com")
      end

      it "extracts product information from descriptions" do
        code = <<~AUA
          type Product = { name: Str, price: Str, category: Str }
          description = "Apple iPhone 14 Pro - Latest smartphone with advanced camera system. Price: $999"
          product = description as Product
          product.name
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("iphone")
      end
    end

    describe "list casting" do
      it "casts natural language to lists" do
        code = <<~AUA
          text = "apples; bananas; and oranges"
          items = text as List
          items
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::List)

        # Check that common fruits are extracted
        fruit_values = result.values.map(&:value).join(" ").downcase
        expect(fruit_values).to include("apple")
        expect(fruit_values).to include("banana")
        expect(fruit_values).to include("orange")

        # Check that at least 3 items were extracted
        # expect(result.values.length).to be >= 3
      end

      it "casts structured text with lists to record types" do
        code = <<~AUA
          type Character = { name: Str, level: Int, items: List }
          text = "Meet our hero Alice, she is level 15 and carries a sword, bow, and health potion"
          character = text as Character
          character.name
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("alice")
      end

      it "handles array literal casting with LLM" do
        code = <<~AUA
          weapons = ["sharp blade", "ranged weapon", "protective gear"] as List
          weapons
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::List)
        expect(result.values.length).to eq(3)
        expect(result.values).to all(be_a(Aua::Str))
        # expect(result.values[0].value).to include("blade")
      end
    end

    describe "complex nested casting" do
      it "extracts nested object structures from natural language" do
        code = <<~AUA
          type Address = { street: Str, city: Str, state: Str }
          type Person = { name: Str, age: Int, address: Address }
          text = "John Doe, 30 years old, lives at 123 Main St, Springfield, IL"
          person = text as Person
          person.address.city
        AUA

        result = Aua.run(code)
        expect(result).to be_a(Aua::Str)
        expect(result.value.downcase).to include("springfield")
      end
    end
  end

  describe "Universal Generative Typecasting" do
    context "when casting between types" do
      describe "generates an appropriate representation for various types" do
        it "strings" do
          expect("1 as Str").to be_aua("one")
          expect("3.14 as Str").to be_aua("π")
        end

        it "booleans" do
          expect('"yes" as Bool').to be_aua(true)
          # expect('"affirmative" as Bool').to be_aua(true)
          # expect('"yeah" as Bool').to be_aua(true)

          expect('"no" as Bool').to be_aua(false)
          expect('"nope" as Bool').to be_aua(false)
          expect('"naw" as Bool').to be_aua(false)
        end

        it "integers" do
          expect("'forty two' as Int").to be_aua(42)
          expect("'negative seven' as Int").to be_aua(-7)
        end

        it "enums" do
          expect("type YesNo = 'yes' | 'no'; 'ok' as YesNo").to be_aua("yes")
          expect("'nope' as YesNo").to be_aua("no")
        end

        it "nihil" do
          expect("nihil as Str").to be_aua("")
          # expect("nihil as Str").to be_aua("the empty string")
          expect("nihil as Bool").to be_aua(false)
        end
      end
    end
  end
end
