# frozen_string_literal: true

module Aua
  # The base object for all Aua values.
  class Obj
    def klass = Klass.klass
    def inspect = "<#{self.class.name} #{introspect}>"
    def introspect = ""
    def pretty = introspect
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
end
