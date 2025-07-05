# frozen_string_literal: true

module Aua
  module Registry
    class Store
      attr_reader :store

      def initialize
        @store = {}
      end

      def [](aisle) = @store[aisle] ||= {}
    end
  end

  # Global state aggregator for Aua runtime metadata
  Methods = Registry::Store.new

  # Base class for all Aua objects - provides common interface
  class Base
    # Common initialization for all Aua objects
    def initialize
      # Base initialization - can be extended by subclasses
    end

    def aura_methods = self.class.aura_methods

    def aura_respond_to?(method_name)
      self.class.aura_methods.include?(method_name)
    end

    def aura_send(method_name, *args)
      unless aura_respond_to?(method_name)
        raise NoMethodError, "Method \\#{method_name} not defined for \\#{self.class.name}"
      end

      meth = self.class.aura_method(method_name)
      # m = meth
      instance_exec(
        *args,
        &meth
      )
    end

    def self.aura_methods = Methods[name]

    def self.aura_method(name)
      raise NoMethodError, "Method #{name} not defined for #{self.name}" unless aura_methods.key?(name)

      meth = aura_methods[name]
      raise TypeError, "Aura method #{name} must be a Proc, got #{meth.class}" unless meth.is_a?(Proc)

      meth
    end

    # Define a new Aura method for the class.
    #
    # @param name [Symbol] The name of the method.
    # @param block [Proc] The block that implements the method.
    #
    # @example
    #   Aua::Obj.define_aura_method(:my_method) { |arg| Aua.logger.info arg }
    #
    def self.define_aura_method(name, &block)
      aura_methods[name] = block # : aura_meth
    end
  end

  # The base object for all Aua values.
  class Obj < Base
    def klass = Klass.klass
    def inspect = "<#{self.class.name} #{introspect}>"
    def introspect = ""
    def pretty = introspect
    def self.describe(message) = define_aura_method(:describe) { message }

    define_aura_method(:dup) { "dup'd" }
  end

  # The class object for Aua types.
  class Klass < Obj
    attr_reader :name

    def initialize(name, parent = nil)
      super()
      @name = name
      @parent = parent
    end

    def klass = self.class.klass

    def self.klass = @klass ||= Klass.new("Klass", nil)
    def self.obj   = @obj ||= Klass.new("Obj", klass)

    def introspect = @name

    def schema_classes
      {
        "Nihil" => Nihil,
        "Int" => Int,
        "Float" => Float,
        "Bool" => Bool,
        "Str" => Str,
        "Time" => Time,
        "List" => List
      }
    end

    def json_schema
      schema_class = schema_classes[@name]
      return schema_class.json_schema if schema_class

      raise "Not a primitive type: #{@name}" unless @parent.nil?
    end

    def construct(val)
      case @name
      when "Nihil", "Int", "Float", "Bool", "Str", "Time"
        schema_classes[@name].new(val)
      when "List" then construct_list(val)
      else
        validate_primitive_type!
      end
    end

    private

    def construct_list(val)
      # NOTE: feels like we should try to convert each item to Aua-like not just string?
      aua_values = val.map { |item| Aua::Str.new(item.to_s) }
      Aua::List.new(aua_values)
    end

    def validate_primitive_type!
      raise "Not a primitive type: #{@name}" unless @parent.nil?
    end
  end

  # The 'nothing' value in Aua.
  class Nihil < Obj
    def klass
      Klass.obj # : Klass
    end

    def name = "nothing"
    def value = nil
    def self.klass = @klass ||= Klass.new("Nihil", nil)

    def self.json_schema
      { type: "object", properties: { value: { type: "null" } }, required: ["value"] }
    end
  end

  # Integer value in Aua.
  class Int < Obj
    def initialize(value)
      super()
      @value = value
    end

    # def klass = Klass.new("Int", Klass.obj)
    def name = "int"
    def introspect = @value.inspect
    def self.klass = @klass ||= Klass.new("Int", Klass.obj)

    attr_reader :value

    define_aura_method(:+) { Int.new(@value + _1.aura_send(:to_i)) }
    define_aura_method(:-) { Int.new(@value - _1.aura_send(:to_i)) }
    define_aura_method(:*) { Int.new(@value * _1.aura_send(:to_i)) }
    define_aura_method(:/) { Int.new(@value / _1.aura_send(:to_i)) }
    define_aura_method(:eq) { Bool.new(@value == _1.value) }
    define_aura_method(:gt) do |other|
      Bool.new(@value > other.value)
    end
    define_aura_method(:lt) { Bool.new(@value < _1.value) }
    define_aura_method(:gte) { Bool.new(@value >= _1.value) }
    define_aura_method(:lte) { Bool.new(@value <= _1.value) }

    define_aura_method(:to_i) { @value }
    define_aura_method(:to_s) { @value.to_s }

    def self.json_schema
      { type: "object", properties: { value: { type: "integer" } }, required: ["value"] }
    end
  end

  # Floating-point value in Aua.
  class Float < Obj
    def initialize(value)
      super()
      @value = value
    end

    def name = "float"
    def introspect = @value.inspect
    def self.klass = @klass ||= Klass.new("Float", Klass.obj)

    attr_reader :value

    define_aura_method(:eq) { Bool.new(@value == _1.value) }
    define_aura_method(:gt) { Bool.new(@value > _1.value) }
    define_aura_method(:lt) { Bool.new(@value < _1.value) }
    define_aura_method(:gte) { Bool.new(@value >= _1.value) }
    define_aura_method(:lte) { Bool.new(@value <= _1.value) }

    def self.json_schema
      { type: "object", properties: { value: { type: "number" } }, required: ["value"] }
    end
  end

  # Boolean value in Aua.
  class Bool < Obj
    def initialize(value)
      super()
      @value = value

      Aua.logger.info("Bool#initialize") do
        "Initialized Bool with value: #{@value.inspect}"
      end
    end

    # def klass = Klass.new("Bool", Klass.obj)
    def name = "bool"
    def introspect = !!@value ? "true" : "false"
    def self.klass = @klass ||= Klass.new("Bool", Klass.obj)

    attr_reader :value

    define_aura_method(:to_s) { introspect }
    define_aura_method(:to_i) { Int.new(@value ? 1 : 0) }
    define_aura_method(:eq) { Bool.new(@value == _1.value) }
    define_aura_method(:gt) { Bool.new(@value && !_1.value) }  # true > false
    define_aura_method(:lt) { Bool.new(!@value && _1.value) }  # false < true
    define_aura_method(:gte) { Bool.new(@value || !_1.value) }
    define_aura_method(:lte) { Bool.new(!@value || _1.value) }
    define_aura_method(:and) { Bool.new(@value && _1.value) }  # logical AND
    define_aura_method(:or) { Bool.new(@value || _1.value) }   # logical OR
    define_aura_method(:not) { Bool.new(!@value) } # logical NOT

    def self.json_schema
      { type: "object", properties: { value: { type: "boolean" } }, required: ["value"] }
    end
  end

  # String value in Aua.
  class Str < Obj
    using Rainbow

    def initialize(value)
      super()
      @value = value
    end

    # def self.klass = @klass ||= Klass.new("Str", Klass.obj)
    # def klass = self.class.klass
    def name = "str"

    def introspect
      str = @value.to_s
      str.length > 80 ? "#{str[0..77]}..." : str
    end

    def self.klass = @klass ||= Klass.new("Str", Klass.obj)

    attr_reader :value

    define_aura_method(:eq) { Bool.new(@value == _1.value) }
    define_aura_method(:+) { Str.new(@value + _1.value.to_s) } # String concatenation
    define_aura_method(:gt) { Bool.new(@value > _1.value) } # lexicographic comparison
    define_aura_method(:lt) { Bool.new(@value < _1.value) }
    define_aura_method(:gte) { Bool.new(@value >= _1.value) }
    define_aura_method(:lte) { Bool.new(@value <= _1.value) }

    def self.json_schema
      { type: "object", properties: { value: { type: "string" } }, required: ["value"] }
    end
  end

  # Timestamp value in Aua.
  class Time < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Time", Klass.obj)
    def name = "time"
    def introspect = @value.strftime("%Y-%m-%d %H:%M:%S")
    def self.klass = @klass ||= Klass.new("Time", Klass.obj)

    def self.now = new(::Time.now)

    def to_s = @value.strftime("%Y-%m-%d %H:%M:%S")

    attr_reader :value

    def self.json_schema
      { type: "object", properties: { value: { type: "string", format: "date-time" } }, required: ["value"] }
    end
  end

  # Array value in Aua.
  class List < Obj
    describe <<~GUIDANCE
      Represents a list of values in Aua.
      Can contain any Aua objects, including other lists.
      Provides methods for accessing and manipulating the list.
    GUIDANCE

    def initialize(values = [])
      super()
      @values = values
    end

    def name = "list"
    def introspect = "[#{@values.map(&:introspect).join(", ")}]"
    def self.klass = @klass ||= Klass.new("List", Klass.obj)

    attr_reader :values

    def self.json_schema
      { type: "object", properties: { value: { type: "array", items: { type: "string" } } }, required: ["value"] }
    end
  end

  # Structured object for record types
  class RecordObject < Obj
    def initialize(type_name, field_definitions, values)
      super()
      @type_name = type_name
      @field_definitions = field_definitions
      @values = values || {}
    end

    attr_reader :type_name, :field_definitions, :values

    def name = @type_name
    def introspect = "#{@type_name} #{@values.inspect}"

    # Support member access
    def get_field(field_name)
      raise Error, "Field '#{field_name}' not found in #{@type_name}" unless @values.key?(field_name)

      @values[field_name]
    end

    # Support setting field values (for construction)
    def set_field(field_name, value)
      @values[field_name] = value
    end

    # Get the Klass for this record type
    def klass
      # This would need to be looked up from the type registry
      # For now, create a simple klass
      @klass ||= Klass.new(@type_name, Klass.obj)
    end
  end

  # Object literal for untyped record-like structures
  class ObjectLiteral < Obj
    define_aura_method(:dup) { ObjectLiteral.new(@values.dup) }

    def initialize(values)
      super()
      @values = values || {}
    end

    attr_reader :values

    def name = "object"
    def introspect = @values.inspect

    # Support member access
    def get_field(field_name)
      raise Error, "Field '#{field_name}' not found in object literal" unless @values.key?(field_name)

      @values[field_name]
    end

    # Check if a field exists
    def has_field?(field_name)
      @values.key?(field_name)
    end

    # Create a new object with an updated field (functional update)
    def set_field(field_name, new_value)
      raise Error, "Field '#{field_name}' not found in object literal" unless @values.key?(field_name)

      # if we wanted functional update
      # new_values = @values.dup
      # new_values[field_name] = new_value
      # ObjectLiteral.new(new_values)

      @values[field_name] = new_value
    end

    def klass
      @klass ||= Klass.new("Object", Klass.obj)
    end
  end

  # Model for user-defined functions (first-class functions with closures)
  class Function < Obj
    attr_reader :name, :parameters, :body, :closure_env

    def initialize(name:, parameters:, body:) # , closure_env:)
      super()
      @name = name
      @parameters = parameters
      @body = body
      @closure_env = nil # closure_env
    end

    def enclose(env)
      @closure_env = env.dup.freeze
      self
    end

    def klass
      @klass ||= Klass.new("Function", Klass.obj)
    end

    def introspect
      param_str = @parameters.map { |p| p.is_a?(Symbol) ? p.to_s : p.inspect }.join(", ")
      "fun #{@name}(#{param_str})"
    end

    def pretty
      introspect
    end

    # Check if this function can be called with the given number of arguments
    def callable_with?(arg_count)
      @parameters.length == arg_count
    end

    # For first-class function support, we need to make functions callable
    # This will be used by the VM when a function is called as a value
    def call(vm, arguments)
      vm.eval_user_function(self, arguments)
    end

    def json_schema
      {
        type: "object",
        properties: {
          name: { type: "string", description: "Name of the function" },
          parameters: {
            type: "array",
            items: { type: "string" },
            description: "Parameter names for the function"
          },
          body: {
            type: "string",
            description: "Valid Aura code for the function body"
          }
        },
        required: %w[name parameters body],
        description: "A user-defined function with parameters and body"
      }
    end

    # Convert this Function object to the hash format expected by VM
    def to_callable
      {
        type: :user_function,
        name: @name,
        parameters: @parameters,
        body: @body,
        closure_env: @closure_env
      }
    end

    def self.json_schema
      {
        type: "object",
        properties: {
          name: { type: "string", description: "Name of the function" },
          parameters: {
            type: "array",
            items: { type: "string" },
            description: "Parameter names for the function"
          },
          body: {
            type: "string",
            description: "Valid Aura code for the function body"
          }
        },
        required: %w[name parameters body],
        description: "A user-defined function with parameters and body"
      }
    end

    def self.klass
      @klass ||= Klass.new("Function", Klass.obj)
    end
  end
end
