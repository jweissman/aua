require "spec_helper"

RSpec.describe "TypeRegistry Core Infrastructure" do
  include Aua::Grammar

  let(:registry) { Aua::Runtime::TypeRegistry.new }

  describe "basic type registration and lookup" do
    it "allows registering and looking up AST-based types" do
      union_ast = s(:union_type, %w[active inactive])

      registry.register("Status", union_ast)

      expect(registry.type?("Status")).to be true
      status_type = registry.lookup("Status")
      expect(status_type).to be_a(Aua::Runtime::Union)
    end

    it "returns false for unregistered types" do
      expect(registry.type?("UnknownType")).to be false
    end

    it "returns nil when looking up unregistered types" do
      expect(registry.lookup("UnknownType")).to be nil
    end

    it "handles type registration with complex names" do
      constant_ast = s(:type_constant, s(:simple_str, "localhost"))

      registry.register("app.config.DatabaseHost", constant_ast)

      expect(registry.type?("app.config.DatabaseHost")).to be true
      host_type = registry.lookup("app.config.DatabaseHost")
      expect(host_type).to be_a(Aua::Runtime::Constant)
    end

    it "lists all registered type names" do
      union_ast = s(:union_type, %w[yes no])
      constant_ast = s(:type_constant, s(:simple_str, "default"))

      registry.register("Answer", union_ast)
      registry.register("DefaultValue", constant_ast)

      expect(registry.type_names).to include("Answer", "DefaultValue")
    end
  end

  describe "union type creation" do
    it "creates union types from AST nodes" do
      union_ast = s(:union_type, %w[low medium high])

      registry.register("Priority", union_ast)

      expect(registry.type?("Priority")).to be true
      priority_type = registry.lookup("Priority")
      expect(priority_type).to be_a(Aua::Runtime::Union)
      expect(priority_type.name).to eq("Priority")
    end
  end

  describe "constant type creation" do
    it "creates constant types for literal values" do
      constant_ast = s(:type_constant, s(:simple_str, "v1.0"))

      registry.register("API_VERSION", constant_ast)

      expect(registry.type?("API_VERSION")).to be true
      version_type = registry.lookup("API_VERSION")
      expect(version_type).to be_a(Aua::Runtime::Constant)
    end
  end

  describe "reference type creation" do
    it "creates reference types for indirect type lookup" do
      # First register the target type
      target_ast = s(:union_type, %w[enabled disabled])
      registry.register("FeatureState", target_ast)

      # Then create a reference to it
      reference_ast = s(:type_reference, "FeatureState")

      registry.register("ToggleState", reference_ast)

      expect(registry.type?("ToggleState")).to be true
      toggle_type = registry.lookup("ToggleState")
      expect(toggle_type).to be_a(Aua::Runtime::Reference)
    end
  end

  describe "error handling and edge cases" do
    it "raises appropriate errors for unknown type definitions" do
      invalid_ast = s(:unknown_type, "invalid")

      expect do
        registry.register("InvalidType", invalid_ast)
      end.to raise_error(Aua::Error, /Unknown type definition/)
    end

    it "handles re-registration of existing types" do
      union_ast1 = s(:union_type, ["option1"])
      s(:union_type, ["option2"])

      registry.register("OverwriteTest", union_ast1)
      # Should use the latest registration
      overwrite_type = registry.lookup("OverwriteTest")
      expect(overwrite_type).to be_a(Aua::Runtime::Union)
    end
  end

  describe "value wrapping utility" do
    it "wraps basic Ruby values in appropriate Aua objects" do
      expect(registry.wrap_value(42)).to be_a(Aua::Int)
      expect(registry.wrap_value(3.14)).to be_a(Aua::Float)
      expect(registry.wrap_value("hello")).to be_a(Aua::Str)
      expect(registry.wrap_value(true)).to be_a(Aua::Bool)
      expect(registry.wrap_value(false)).to be_a(Aua::Bool)
    end

    it "wraps complex objects recursively" do
      hash_value = { "name" => "test", "count" => 5 }
      wrapped = registry.wrap_value(hash_value)

      expect(wrapped).to be_a(Aua::ObjectLiteral)
    end

    it "wraps arrays into Aua Lists" do
      array_value = [1, 2, "three"]
      wrapped = registry.wrap_value(array_value)

      expect(wrapped).to be_a(Aua::List)
    end
  end

  describe "integration scenarios" do
    it "supports a complete type hierarchy" do
      # Create base union type
      status_ast = s(:union_type, %w[pending approved rejected])
      registry.register("ApprovalStatus", status_ast)

      # Create constant type
      default_ast = s(:type_constant, s(:simple_str, "pending"))
      registry.register("DEFAULT_STATUS", default_ast)

      # Create reference type
      alias_ast = s(:type_reference, "ApprovalStatus")
      registry.register("RequestStatus", alias_ast)

      # Verify all types exist
      expect(registry.type?("ApprovalStatus")).to be true
      expect(registry.type?("DEFAULT_STATUS")).to be true
      expect(registry.type?("RequestStatus")).to be true

      # Verify type relationships
      approval_type = registry.lookup("ApprovalStatus")
      default_type = registry.lookup("DEFAULT_STATUS")
      request_type = registry.lookup("RequestStatus")

      expect(approval_type).to be_a(Aua::Runtime::Union)
      expect(default_type).to be_a(Aua::Runtime::Constant)
      expect(request_type).to be_a(Aua::Runtime::Reference)
    end
  end
end
