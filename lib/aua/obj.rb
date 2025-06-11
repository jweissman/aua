# frozen_string_literal: true

module Aua
  # The base object for all Aua values.
  class Obj
    def klass = Klass.klass
    def inspect = "<#{self.class.name} #{introspect}>"
    def introspect = ""
    def pretty = introspect
    def aura_methods = self.class.aura_methods

    def aura_respond_to?(method_name)
      self.class.aura_methods.include?(method_name)
    end

    def aura_send(method_name, *)
      unless aura_respond_to?(method_name)
        raise NoMethodError, "Method #{method_name} not defined for #{self.class.name}"
      end

      meth = self.class.aura_method(method_name)
      instance_exec(*, &meth)
    end

    def self.aura_methods
      @@method_store ||= {}
      @@method_store[name] ||= {}
      @@method_store[name] # Hash[Symbol, Proc]
    end

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
    #   Aua::Obj.define_aura_method(:my_method) { |arg| puts arg }
    #
    def self.define_aura_method(name, &block)
      aura_methods[name] = block # Store as Proc, not UnboundMethod
      print "#{self.name.split("::").last}##{name} "
    end
  end

  # The class object for Aua types.
  class Klass < Obj
    def initialize(name, parent = nil)
      super()
      @name = name
      @parent = parent
    end

    def klass = send :itself

    def self.klass = Klass.new("Klass", klass)
    def self.obj = Klass.new("Obj", klass)

    def introspect = @name
  end

  # The 'nothing' value in Aua.
  class Nihil < Obj
    def klass
      Klass.obj # : Klass
    end

    def name = "nothing"
    def value = nil
  end

  # Integer value in Aua.
  class Int < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Int", Klass.obj)
    def name = "int"
    def introspect = @value.inspect

    attr_reader :value

    define_aura_method(:+) { Int.new(@value + _1.aura_send(:to_i)) }
    define_aura_method(:-) { Int.new(@value - _1.aura_send(:to_i)) }
    define_aura_method(:*) { Int.new(@value * _1.aura_send(:to_i)) }
    define_aura_method(:/) { Int.new(@value / _1.aura_send(:to_i)) }

    define_aura_method(:to_i) { @value }
  end

  # Floating-point value in Aua.
  class Float < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Float", Klass.obj)
    def name = "float"
    def introspect = @value.inspect

    attr_reader :value
  end

  # Boolean value in Aua.
  class Bool < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Bool", Klass.obj)
    def name = "bool"
    def introspect = @value.inspect ? "true" : "false"

    attr_reader :value

    define_aura_method(:to_i) { Int.new(@value ? 1 : 0) }
  end

  # String value in Aua.
  class Str < Obj
    def initialize(value)
      super()
      @value = value
    end

    def klass = Klass.new("Str", Klass.obj)
    def name = "str"
    def introspect = @value.inspect

    attr_reader :value
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

    def self.now = new(::Time.now)

    def to_s = @value.strftime("%Y-%m-%d %H:%M:%S")

    attr_reader :value
  end
end
