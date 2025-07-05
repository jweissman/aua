# Aua Refactoring Analysis & Roadmap

## Critical Refactoring Opportunities

### 1. Parser Architecture Simplification

#### Current Issues

The parser has grown organically and shows signs of complexity:

- **Mixed Responsibilities**: Parse handles both grammar rules and AST construction
- **String Interpolation Complexity**: Multiple state machines for string parsing
- **Precedence Handling**: Manual precedence checking scattered through binop parsing
- **Error Recovery**: Limited error recovery mechanisms

#### Proposed Solution: Parser Combinator Approach

```ruby
# New parser architecture using combinators
module Aua::Parser
  class Combinator
    # Basic combinators
    def self.token(type) = ->(tokens) { tokens.first&.type == type ? [tokens.first, tokens[1..]] : nil }
    def self.sequence(*parsers) = ->(tokens) { ... }
    def self.choice(*parsers) = ->(tokens) { ... }
    def self.optional(parser) = ->(tokens) { ... }
    def self.many(parser) = ->(tokens) { ... }

    # Grammar-specific combinators
    def self.binary_op(min_prec = 0) = ->(tokens) { ... }
    def self.expression = ->(tokens) { ... }
  end

  # Clean grammar definition
  class Grammar < Combinator
    Primary = choice(
      token(:int).map { |t| AST::Node.new(:int, t.value) },
      token(:str).map { |t| AST::Node.new(:str, t.value) },
      sequence(token(:lparen), expression, token(:rparen)).map { |_, expr, _| expr }
    )

    Expression = binary_op(0)
  end
end
```

### 2. VM Instruction Set Unification

#### Current Issues

- **Mixed Abstraction Levels**: Some operations are high-level statements, others are low-level
- **Inconsistent Evaluation**: Multiple evaluation paths through the VM
- **Type System Integration**: Type checking scattered across evaluation

#### Proposed Solution: SSA-Style IR

```ruby
module Aua::Runtime::IR
  # Single Static Assignment intermediate representation
  class Instruction < Data.define(:op, :args, :type, :result)
    def self.assign(var, value) = new(:assign, [var, value], :unit, var)
    def self.call(func, args) = new(:call, [func, *args], :dynamic, "%#{next_id}")
    def self.cast(value, type) = new(:cast, [value, type], type, "%#{next_id}")
    def self.phi(values) = new(:phi, values, :dynamic, "%#{next_id}")
  end

  class BasicBlock < Data.define(:label, :instructions, :successors)
  end

  class Function < Data.define(:name, :params, :blocks)
  end
end
```

### 3. Type System Consolidation

#### Current Issues

- **Scattered Type Logic**: Type checking in VM, casting in translator, definitions in registry
- **Limited Inference**: No static type analysis
- **Inconsistent Error Messages**: Type errors vary in quality

#### Proposed Solution: Unified Type Checker

```ruby
module Aua::Types
  class Checker
    def initialize(registry)
      @registry = registry
      @constraints = []
      @type_vars = {}
    end

    def check_program(ast)
      # Hindley-Milner style inference
      type_env = initial_environment
      expr_type = infer_type(ast, type_env)
      solve_constraints
      expr_type
    end

    def infer_type(node, env)
      case node.type
      when :int then IntType.new
      when :str then StrType.new
      when :call then infer_call(node, env)
      when :binop then infer_binop(node, env)
      else UnknownType.new
      end
    end
  end
end
```

## Performance Optimization Strategy

### Phase 1: Baseline Measurements

```ruby
# Add performance tracking
module Aua::Profiler
  def self.profile(description)
    start = Time.now
    result = yield
    elapsed = Time.now - start
    puts "#{description}: #{elapsed}s"
    result
  end
end

# Usage throughout codebase
def evaluate!(ast)
  Profiler.profile("AST Evaluation") do
    # existing evaluation logic
  end
end
```

### Phase 2: Compilation Pipeline

```ruby
module Aua::Compiler
  class Pipeline
    def compile(source)
      tokens = profile("Lexing") { lex(source) }
      ast = profile("Parsing") { parse(tokens) }
      ir = profile("IR Generation") { generate_ir(ast) }
      optimized = profile("Optimization") { optimize(ir) }
      bytecode = profile("Code Generation") { generate_bytecode(optimized) }
      bytecode
    end
  end

  # SSA-based optimizations
  class Optimizer
    def optimize(ir)
      ir = dead_code_elimination(ir)
      ir = constant_propagation(ir)
      ir = common_subexpression_elimination(ir)
      ir
    end
  end
end
```

### Phase 3: JIT Integration

```ruby
module Aua::JIT
  class HotSpotCompiler
    def initialize
      @call_counts = Hash.new(0)
      @compiled_functions = {}
    end

    def should_compile?(function_name)
      @call_counts[function_name] += 1
      @call_counts[function_name] > 100  # Compile after 100 calls
    end
  end
end
```

## Architectural Improvements

### Error Handling & Source Maps

```ruby
module Aua::Error
  class Context < Data.define(:source, :line, :column, :length)
    def highlight_source
      lines = source.split("\n")
      lines[line - 1].tap do |line_text|
        puts line_text
        puts " " * (column - 1) + "^" * length
      end
    end
  end

  class AuaError < StandardError
    attr_reader :context, :error_type

    def initialize(message, context: nil, type: :runtime)
      super(message)
      @context = context
      @error_type = type
    end

    def to_s
      result = super
      if @context
        result += "\n  at #{@context.source}:#{@context.line}:#{@context.column}"
        result += "\n\n"
        result += @context.highlight_source
      end
      result
    end
  end
end
```

### Built-in Function System

```ruby
module Aua::Builtins
  class Registry
    def initialize
      @functions = {}
    end

    def register(name, arity: nil, &block)
      @functions[name] = Function.new(name, arity, block)
    end

    def call(name, args)
      func = @functions[name] or raise Error::AuaError.new("Unknown function: #{name}")
      func.call(args)
    end
  end

  # Register standard library
  Registry.new.tap do |reg|
    reg.register(:say, arity: 1) { |msg| puts msg.to_s; Nihil.new }
    reg.register(:ask, arity: 1) { |prompt| Str.new(gets.chomp) }
    reg.register(:inspect, arity: 1) { |obj| Str.new(obj.inspect) }
    reg.register(:typeof, arity: 1) { |obj| Str.new(obj.class.name) }
  end
end
```

## Implementation Priority

### Phase 1: Foundation (2-3 weeks)

1. **Error System**: Implement comprehensive error handling with source maps
2. **Type Inference**: Basic Hindley-Milner inference for core types
3. **Testing Infrastructure**: Property-based testing expansion
4. **Documentation**: Complete language reference and manual

### Phase 2: Performance (3-4 weeks)

1. **IR Design**: Implement SSA-style intermediate representation
2. **Optimization Passes**: Dead code elimination, constant propagation
3. **Compilation Pipeline**: AST → IR → Bytecode → Execution
4. **Profiling Tools**: Performance measurement and bottleneck identification

### Phase 3: Advanced Features (4-6 weeks)

1. **Method System**: User-defined classes and methods
2. **Pattern Matching**: Destructuring and dispatch
3. **Generic Types**: Parametric polymorphism
4. **Module System**: Namespaces and imports

### Phase 4: Self-Hosting (6+ weeks)

1. **Bootstrap Compiler**: Aua-in-Aua compiler
2. **Standard Library**: Comprehensive built-in functions
3. **Package Manager**: Dependency management
4. **Development Tools**: Debugger, profiler, language server

## Near-Term Wins

### 1. typeof() Built-in

```ruby
def builtin_typeof(obj)
  type_name = case obj
              when Int then "Int"
              when Str then "Str"
              when Bool then "Bool"
              when Float then "Float"
              when Function then "Function"
              when ObjectLiteral then "Object"
              when List then "List"
              else obj.class.name.split("::").last
              end
  Str.new(type_name)
end
```

### 2. Better Error Messages

```ruby
class ParseError < Error::AuaError
  def self.unexpected_token(expected, actual, context)
    message = "Expected #{expected}, got #{actual.type}"
    new(message, context: context, type: :parse)
  end
end
```

### 3. Standard Library Expansion

```ruby
# String methods
class Str
  def aura_methods
    {
      length: -> { Int.new(@value.length) },
      upcase: -> { Str.new(@value.upcase) },
      downcase: -> { Str.new(@value.downcase) },
      split: ->(sep) { List.new(@value.split(sep.value).map { |s| Str.new(s) }) }
    }
  end
end

# Array methods
class List
  def aura_methods
    {
      length: -> { Int.new(@elements.length) },
      first: -> { @elements.first || Nihil.new },
      last: -> { @elements.last || Nihil.new },
      map: ->(func) { List.new(@elements.map { |elem| func.call([elem]) }) }
    }
  end
end
```

## Testing Strategy

### Property-Based Testing Expansion

```ruby
module Aua::Properties
  # Type preservation
  def type_preservation
    forall(aua_expression) do |expr|
      result = Aua.run(expr)
      inferred_type = TypeChecker.infer(expr)
      actual_type = typeof(result)
      actual_type.compatible_with?(inferred_type)
    end
  end

  # Evaluation equivalence
  def evaluation_equivalence
    forall(aua_expression) do |expr|
      result1 = VM.new.evaluate(expr)
      result2 = CompiledVM.new.evaluate(expr)
      result1.equivalent?(result2)
    end
  end
end
```

### Performance Regression Testing

```ruby
module Aua::Benchmarks
  def self.benchmark_suite
    {
      fibonacci: ->(n) { "fun fib(n) if n <= 1 then n else fib(n-1) + fib(n-2) end; fib(#{n})" },
      factorial: ->(n) { "fun fact(n) if n <= 1 then 1 else n * fact(n-1) end; fact(#{n})" },
      array_ops: ->(size) { "[#{(1..size).to_a.join(', ')}].map(x => x * 2).reduce((a, b) => a + b)" }
    }
  end

  def self.run_benchmarks
    benchmark_suite.each do |name, code_gen|
      time = Benchmark.measure { Aua.run(code_gen.call(20)) }
      puts "#{name}: #{time.real}s"
    end
  end
end
```

This refactoring roadmap provides a clear path forward while maintaining the innovative AI-integration features that make Aua unique. The focus on performance and tooling will make it suitable for more serious development work while preserving its experimental, AI-native character.
