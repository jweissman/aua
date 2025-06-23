require "spec_helper"

RSpec.describe "Equality Comparison Features" do
  describe "numeric equality" do
    it "compares equal integers" do
      expect("1 == 1").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "compares unequal integers" do
      expect("1 == 0").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "compares equal floats" do
      expect("3.14 == 3.14").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "compares unequal floats" do
      expect("3.14 == 2.71").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "compares int and float of same value" do
      expect("5 == 5.0").to be_aua(true).and_be_a(Aua::Bool)
    end
  end

  describe "string equality" do
    it "compares equal strings" do
      expect('"hello" == "hello"').to be_aua(true).and_be_a(Aua::Bool)
    end

    it "compares unequal strings" do
      expect('"hello" == "world"').to be_aua(false).and_be_a(Aua::Bool)
    end

    it "compares empty strings" do
      expect('"" == ""').to be_aua(true).and_be_a(Aua::Bool)
    end
  end

  describe "boolean equality" do
    it "compares equal booleans" do
      expect("true == true").to be_aua(true).and_be_a(Aua::Bool)
      expect("false == false").to be_aua(true).and_be_a(Aua::Bool)
    end

    it "compares unequal booleans" do
      expect("true == false").to be_aua(false).and_be_a(Aua::Bool)
      expect("false == true").to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  describe "mixed type equality" do
    it "compares different types as unequal" do
      expect('"5" == 5').to be_aua(false).and_be_a(Aua::Bool)
      expect("true == 1").to be_aua(false).and_be_a(Aua::Bool)
      expect('"true" == true').to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  describe "equality with variables" do
    it "compares variables" do
      expect("x = 5; y = 5; x == y").to be_aua(true).and_be_a(Aua::Bool)
      expect("x = 5; y = 3; x == y").to be_aua(false).and_be_a(Aua::Bool)
    end

    it "compares variable with literal" do
      expect('name = "Alice"; name == "Alice"').to be_aua(true).and_be_a(Aua::Bool)
      expect('name = "Alice"; name == "Bob"').to be_aua(false).and_be_a(Aua::Bool)
    end
  end

  describe "equality in conditional expressions" do
    it "uses equality in if statements" do
      expect('if 1 == 1 then "yes" else "no"').to be_aua("yes").and_be_a(Aua::Str)
      expect('if 1 == 0 then "yes" else "no"').to be_aua("no").and_be_a(Aua::Str)
    end

    it "uses equality with variables in conditionals" do
      expect('x = 5; if x == 5 then "match" else "no match"').to be_aua("match").and_be_a(Aua::Str)
      expect('x = 3; if x == 5 then "match" else "no match"').to be_aua("no match").and_be_a(Aua::Str)
    end
  end
end
