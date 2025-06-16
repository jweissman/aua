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

  class Base
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
      print "#{self.name.split("::").last}##{name} "
    end

    def klass = self.class.klass
    # def self.klass   = @klass_obj ||= Klass.new("Obj", klass)
  end

  # The class object for Aua types.
  class Klass < Obj
    def initialize(name, parent = nil)
      super()
      @name = name
      @parent = parent
    end

    def klass = self.class.klass

    def self.klass = @klass ||= Klass.new("Klass", nil)
    def self.obj   = @klass_obj ||= Klass.new("Obj", klass)

    def introspect = @name
  end

  # The 'nothing' value in Aua.
  class Nihil < Obj
    def klass
      Klass.obj # : Klass
    end

    def name = "nothing"
    def value = nil
    def self.klass = @klass ||= Klass.new("Nihil", nil)
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

    define_aura_method(:to_i) { @value }
    define_aura_method(:to_s) { @value.to_s }
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
  end

  # Boolean value in Aua.
  class Bool < Obj
    def initialize(value)
      super()
      @value = value
    end

    # def klass = Klass.new("Bool", Klass.obj)
    def name = "bool"
    def introspect = @value.inspect ? "true" : "false"
    def self.klass = @klass ||= Klass.new("Bool", Klass.obj)

    attr_reader :value

    define_aura_method(:to_i) { Int.new(@value ? 1 : 0) }
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
    def introspect = @value.inspect[1..80]&.concat(@value.length > 80 ? "..." : "") || ""
    def self.klass = @klass ||= Klass.new("Str", Klass.obj)

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
    def self.klass = @klass ||= Klass.new("Time", Klass.obj)

    def self.now = new(::Time.now)

    def to_s = @value.strftime("%Y-%m-%d %H:%M:%S")

    attr_reader :value
  end
end
