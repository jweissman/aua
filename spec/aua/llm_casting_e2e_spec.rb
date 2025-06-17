# frozen_string_literal: true

require "spec_helper"

RSpec.describe "LLM Casting End-to-End", skip: false do
  describe "structured data extraction" do
    it "extracts person data from natural language", :llm_required do
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

    it "parses contact information from email signatures", :llm_required do
      code = <<~AUA
        type Contact = { name: Str, email: Str, phone: Str }
        signature = "Best regards,\\nJohn Smith\\njohn.smith@example.com\\n(555) 123-4567"
        contact = signature as Contact
        contact.email
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value).to include("john.smith@example.com")
    end

    it "extracts product data from descriptions", :llm_required do
      code = <<~AUA
        type Product = { name: Str, price: Int, category: Str }
        description = "MacBook Pro 16-inch laptop, perfect for developers. Price: $2499. Electronics category."
        product = description as Product
        product.price
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to be_between(2000, 3000)
    end

    it "parses coordinates from various formats", :llm_required do
      code = <<~AUA
        type Location = { latitude: Float, longitude: Float }
        gps_string = "Lat: 45.5152° N, Lon: 122.6784° W"
        location = gps_string as Location
        location.latitude
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Float)
      expect(result.value).to be_between(40.0, 50.0)
    end
  end

  describe "data format conversion" do
    it "converts CSV-like data to structured objects", :llm_required do
      code = <<~AUA
        type Employee = { name: Str, department: Str, salary: Int }
        csv_row = "Alice Johnson,Engineering,85000"
        employee = csv_row as Employee
        employee.department
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value.downcase).to include("engineering")
    end

    it "extracts data from log entries", :llm_required do
      code = <<~AUA
        type LogEntry = { timestamp: Str, level: Str, message: Str }
        log_line = "[2024-01-15 14:30:22] ERROR: Database connection failed"
        entry = log_line as LogEntry
        entry.level
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value.upcase).to include("ERROR")
    end

    it "parses configuration from informal text", :llm_required do
      code = <<~AUA
        type Config = { host: Str, port: Int, ssl: Bool }
        config_text = "Connect to database at localhost on port 5432, SSL is enabled"
        config = config_text as Config
        config.port
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(5432)
    end
  end

  describe "complex nested structures" do
    it "extracts nested address information", :llm_required do
      code = <<~AUA
        type Address = { street: Str, city: Str, zip: Str }
        type Customer = { name: Str, address: Address }
        text = "Customer: Bob Wilson lives at 123 Main Street, Springfield, 12345"
        customer = text as Customer
        customer.address.city
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value.downcase).to include("springfield")
    end

    it "parses order data with items", :llm_required do
      code = <<~AUA
        type OrderItem = { name: Str, quantity: Int, price: Float }
        type Order = { id: Str, customer: Str, total: Float }
        order_text = "Order #ORD-001 for Jane Doe: 2x Coffee ($4.50 each), 1x Sandwich ($8.99). Total: $17.99"
        order = order_text as Order
        order.total
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Float)
      expect(result.value).to be_between(15.0, 20.0)
    end
  end

  describe "error handling and edge cases" do
    it "handles ambiguous or incomplete data gracefully", :llm_required do
      code = <<~AUA
        type Person = { name: Str, age: Int, city: Str }
        incomplete_text = "Someone named Mike"
        person = incomplete_text as Person
        person.name
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      expect(result.value.downcase).to include("mike")
    end

    it "provides reasonable defaults for missing numeric data", :llm_required do
      code = <<~AUA
        type Stats = { count: Int, average: Float, max: Int }
        vague_text = "We processed some data and the results were good"
        stats = vague_text as Stats
        stats.count
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      # Should provide some reasonable default, even if 0
      expect(result.value).to be >= 0
    end
  end

  describe "real-world scenarios" do
    it "extracts meeting information from calendar text", :llm_required do
      code = <<~AUA
        type Meeting = { title: Str, date: Str, duration: Int, attendees: Str }
        calendar_entry = "Team Standup on Monday Jan 15th from 9:00-9:30 AM with Alice, Bob, and Carol"
        meeting = calendar_entry as Meeting
        meeting.duration
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to be_between(20, 40) # 30 minutes
    end

    it "parses social media post metadata", :llm_required do
      code = <<~AUA
        type Post = { author: Str, likes: Int, hashtags: Str }
        post_text = "@john_doe: Great day at the beach! #vacation #summer #fun (liked by 42 people)"
        post = post_text as Post
        post.likes
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(42)
    end

    it "extracts weather data from natural descriptions", :llm_required do
      code = <<~AUA
        type Weather = { location: Str, temperature: Int, condition: Str }
        weather_text = "It's sunny and 72 degrees in San Francisco today"
        weather = weather_text as Weather
        weather.temperature
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to be_between(70, 75)
    end

    it "parses financial transaction descriptions", :llm_required do
      code = <<~AUA
        type Transaction = { merchant: Str, amount: Float, category: Str }
        transaction = "Starbucks Coffee - $4.85 - Food & Dining"
        txn = transaction as Transaction
        txn.amount
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Float)
      expect(result.value).to be_between(4.0, 5.0)
    end
  end

  describe "data validation and correction" do
    it "corrects common data entry errors", :llm_required do
      code = <<~AUA
        type Person = { name: Str, age: Int, email: Str }
        messy_data = "Name: john smith (age: twenty-five) Email: john@gmailcom"
        person = messy_data as Person
        person.age
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Int)
      expect(result.value).to eq(25)
    end

    it "normalizes phone number formats", :llm_required do
      code = <<~AUA
        type Contact = { name: Str, phone: Str }
        contact_info = "Call me! I'm Sarah. My number is five five five one two three four five six seven"
        contact = contact_info as Contact
        contact.phone
      AUA

      result = Aua.run(code)
      expect(result).to be_a(Aua::Str)
      # Should contain digits, possibly formatted
      expect(result.value).to match(/\d/)
    end
  end
end
