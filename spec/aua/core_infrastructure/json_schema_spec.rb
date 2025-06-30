require "spec_helper"

RSpec.describe "JsonSchema Core Infrastructure" do
  include Aua::Grammar

  let(:registry) { Aua::Runtime::TypeRegistry.new }

  describe "record type schemas" do
    it "generates schemas for simple record types" do
      # Create a record type: { name: Str, age: Int }
      field_definitions = [
        { name: "name", type: s(:type_reference, "Str") },
        { name: "age", type: s(:type_reference, "Int") }
      ]

      schema = Aua::Runtime::JsonSchema.for_record_type(field_definitions, registry)

      expect(schema).to eq({
                             type: "object",
                             properties: {
                               value: {
                                 type: "object",
                                 properties: {
                                   "name" => { type: "string" },
                                   "age" => { type: "integer" }
                                 },
                                 required: %w[name age]
                               }
                             }
                           })
    end

    it "generates schemas for mixed primitive types" do
      # Create a record type: { enabled: Bool, score: Float, tags: List }
      field_definitions = [
        { name: "enabled", type: s(:type_reference, "Bool") },
        { name: "score", type: s(:type_reference, "Float") },
        { name: "tags", type: s(:type_reference, "List") }
      ]

      schema = Aua::Runtime::JsonSchema.for_record_type(field_definitions, registry)

      expect(schema[:properties][:value][:properties]).to eq({
                                                               "enabled" => { type: "boolean" },
                                                               "score" => { type: "number" },
                                                               "tags" => { type: "array", items: { type: "string" } }
                                                             })
    end

    it "handles empty record types" do
      field_definitions = []

      schema = Aua::Runtime::JsonSchema.for_record_type(field_definitions, registry)

      expect(schema[:properties][:value][:properties]).to eq({})
      expect(schema[:properties][:value][:required]).to eq([])
    end
  end

  describe "union type schemas" do
    it "generates schemas for string literal unions" do
      # Create union variants: 'active' | 'inactive'
      variants = [
        s(:type_constant, s(:simple_str, "active")),
        s(:type_constant, s(:simple_str, "inactive"))
      ]

      schema = Aua::Runtime::JsonSchema.for_union_type(variants, registry)

      expect(schema).to eq({
                             type: "object",
                             properties: {
                               value: {
                                 type: "string",
                                 enum: %w[active inactive]
                               }
                             }
                           })
    end

    it "generates schemas for mixed union variants" do
      # Create union variants: 'pending' | SomeType
      variants = [
        s(:type_constant, s(:simple_str, "pending")),
        s(:type_reference, "SomeType")
      ]

      schema = Aua::Runtime::JsonSchema.for_union_type(variants, registry)

      # Current implementation includes both string literals and type names
      expect(schema[:properties][:value][:enum]).to eq(%w[pending SomeType])
    end

    it "handles union with only type references" do
      # Create union variants: TypeA | TypeB
      variants = [
        s(:type_reference, "TypeA"),
        s(:type_reference, "TypeB")
      ]

      schema = Aua::Runtime::JsonSchema.for_union_type(variants, registry)

      # Current implementation includes type names in enum
      expect(schema[:properties][:value][:enum]).to eq(%w[TypeA TypeB])
    end
  end

  describe "type reference resolution" do
    it "resolves built-in primitive types correctly" do
      primitives = {
        "Int" => { type: "integer" },
        "Float" => { type: "number" },
        "Str" => { type: "string" },
        "Bool" => { type: "boolean" },
        "List" => { type: "array", items: { type: "string" } }
      }

      primitives.each do |type_name, expected_schema|
        field_def = [{ name: "field", type: s(:type_reference, type_name) }]
        schema = Aua::Runtime::JsonSchema.for_record_type(field_def, registry)

        actual_field_schema = schema[:properties][:value][:properties]["field"]
        expect(actual_field_schema).to eq(expected_schema),
                                       "Expected #{type_name} to produce #{expected_schema}, got #{actual_field_schema}"
      end
    end

    it "resolves user-defined types from registry" do
      # Register a custom union type
      union_ast = s(:union_type, [
                      s(:type_constant, s(:simple_str, "red")),
                      s(:type_constant, s(:simple_str, "blue"))
                    ])
      registry.register("Color", union_ast)

      # Create a record that references the custom type
      field_def = [{ name: "color", type: s(:type_reference, "Color") }]
      schema = Aua::Runtime::JsonSchema.for_record_type(field_def, registry)

      # Should extract the inner enum schema
      color_schema = schema[:properties][:value][:properties]["color"]
      expect(color_schema).to eq({
                                   type: "string",
                                   enum: %w[red blue]
                                 })
    end

    it "handles unknown type references gracefully" do
      field_def = [{ name: "unknown", type: s(:type_reference, "UnknownType") }]
      schema = Aua::Runtime::JsonSchema.for_record_type(field_def, registry)

      unknown_schema = schema[:properties][:value][:properties]["unknown"]
      expect(unknown_schema).to eq({ type: "string" })
    end
  end

  describe "complex type interactions" do
    it "handles nested record types with custom unions" do
      # Register a Status union type
      status_ast = s(:union_type, [
                       s(:type_constant, s(:simple_str, "pending")),
                       s(:type_constant, s(:simple_str, "approved")),
                       s(:type_constant, s(:simple_str, "rejected"))
                     ])
      registry.register("Status", status_ast)

      # Create a record type that uses the Status
      field_definitions = [
        { name: "id", type: s(:type_reference, "Int") },
        { name: "status", type: s(:type_reference, "Status") },
        { name: "notes", type: s(:type_reference, "Str") }
      ]

      schema = Aua::Runtime::JsonSchema.for_record_type(field_definitions, registry)

      expect(schema[:properties][:value][:properties]).to eq({
                                                               "id" => { type: "integer" },
                                                               "status" => { type: "string",
                                                                             enum: %w[pending approved rejected] },
                                                               "notes" => { type: "string" }
                                                             })
    end

    it "handles type constants in record fields" do
      # Create a record with a literal constant field
      field_definitions = [
        { name: "version", type: s(:type_constant, s(:simple_str, "v2.0")) },
        { name: "data", type: s(:type_reference, "Str") }
      ]

      schema = Aua::Runtime::JsonSchema.for_record_type(field_definitions, registry)

      expect(schema[:properties][:value][:properties]).to eq({
                                                               "version" => { enum: ["v2.0"] },
                                                               "data" => { type: "string" }
                                                             })
    end
  end

  describe "error handling" do
    it "raises appropriate errors for unsupported union variants" do
      # Create an invalid union variant type
      invalid_variant = s(:invalid_type, "something")

      expect do
        Aua::Runtime::JsonSchema.for_union_type([invalid_variant], registry)
      end.to raise_error(Aua::Error, /Unsupported union variant: invalid_type/)
    end
  end

  describe "integration with type system" do
    it "supports LLM casting workflows" do
      # This test demonstrates the intended use case for JsonSchema

      # 1. Define a type for game character data
      character_fields = [
        { name: "name", type: s(:type_reference, "Str") },
        { name: "hp", type: s(:type_reference, "Int") },
        { name: "class", type: s(:type_reference, "CharacterClass") }
      ]

      # 2. Register a character class enum
      class_ast = s(:union_type, [
                      s(:type_constant, s(:simple_str, "warrior")),
                      s(:type_constant, s(:simple_str, "mage")),
                      s(:type_constant, s(:simple_str, "rogue"))
                    ])
      registry.register("CharacterClass", class_ast)

      # 3. Generate schema for LLM prompting
      schema = Aua::Runtime::JsonSchema.for_record_type(character_fields, registry)

      # 4. Verify the schema is suitable for LLM consumption
      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:value][:properties]).to include(
        "name" => { type: "string" },
        "hp" => { type: "integer" },
        "class" => { type: "string", enum: %w[warrior mage rogue] }
      )
      expect(schema[:properties][:value][:required]).to eq(%w[name hp class])
    end
  end

  describe "type-level vs runtime union semantics" do
    it "documents the distinction between type-level enums and runtime barred unions" do
      # Type-level enum: type Status = 'pending' | 'approved' | CustomStatusType
      # This is for type checking and type-driven synthesis
      type_level_variants = [
        s(:type_constant, s(:simple_str, "pending")),
        s(:type_constant, s(:simple_str, "approved")),
        s(:type_reference, "CustomStatusType")
      ]

      # Runtime barred union: "Pick status?" ~ ('pending' | 'approved')
      # This is for direct LLM prompting - only literal choices
      runtime_literal_variants = [
        s(:type_constant, s(:simple_str, "pending")),
        s(:type_constant, s(:simple_str, "approved"))
      ]

      # Current implementation treats both the same way
      type_schema = Aua::Runtime::JsonSchema.for_union_type(type_level_variants, registry)
      runtime_schema = Aua::Runtime::JsonSchema.for_union_type(runtime_literal_variants, registry)

      # Type-level includes both literals and type names
      expect(type_schema[:properties][:value][:enum]).to eq(%w[pending approved CustomStatusType])

      # Runtime literals only include actual string choices
      expect(runtime_schema[:properties][:value][:enum]).to eq(%w[pending approved])

      # TODO: Consider if these should be handled differently
      # - Type-level might need to resolve type references to their schemas
      # - Runtime literals should only include string literals for LLM prompting
    end

    it "shows how type references in unions might need different handling" do
      # Register a nested union type
      priority_ast = s(:union_type, [
                         s(:type_constant, s(:simple_str, "low")),
                         s(:type_constant, s(:simple_str, "high"))
                       ])
      registry.register("Priority", priority_ast)

      # Create a union that references the nested type
      mixed_variants = [
        s(:type_constant, s(:simple_str, "urgent")),
        s(:type_reference, "Priority") # This should expand to ["low", "high"]
      ]

      schema = Aua::Runtime::JsonSchema.for_union_type(mixed_variants, registry)

      # Current behavior: includes type name as literal
      expect(schema[:properties][:value][:enum]).to eq(%w[urgent Priority])

      # Potential future behavior: expand type references
      # expect(schema[:properties][:value][:enum]).to eq(["urgent", "low", "high"])
      # OR provide a different method for runtime vs type-level schemas
    end
  end
end
