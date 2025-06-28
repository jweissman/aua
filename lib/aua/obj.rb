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
  end

  # The base object for all Aua values.
  class Obj < Base
    def klass = Klass.klass
    def inspect = "<#{self.class.name} #{introspect}>"
    def introspect = ""
    def pretty = introspect
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
      # print "#{self.name.split("::").last}##{name} "
    end

    # def self.klass   = @klass_obj ||= Klass.new("Obj", klass)
    # define_aura_method(:to_s) { introspect }
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

    def json_schema
      case @name
      when "Nihil"
        Nihil.json_schema
      when "Int"
        Int.json_schema
      when "Float"
        Float.json_schema
      when "Bool"
        Bool.json_schema
      when "Str"
        Str.json_schema
      when "Time"
        Time.json_schema
      when "List"
        List.json_schema
      else
        raise "Not a primitive type: #{@name}" unless @parent.nil?
      end
    end

    def construct(val)
      case @name
      when "Nihil"
        Nihil.new
      when "Int"
        Int.new(val)
      when "Float"
        Float.new(val)
      when "Bool"
        Bool.new(val)
      when "Str"
        Str.new(val)
      when "Time"
        Time.new(val)
      when "List"
        # Convert raw strings to Aua::Str objects
        aua_values = val.map { |item| Aua::Str.new(item.to_s) }
        Aua::List.new(aua_values)
      else
        raise "Not a primitive type: #{@name}" unless @parent.nil?
      end
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
    define_aura_method(:gt) do
      Bool.new(@value > _1.value)
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

    def klass
      @klass ||= Klass.new("Object", Klass.obj)
    end
  end
end
