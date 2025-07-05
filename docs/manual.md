# Aua Programming Manual

## Table of Contents

- [Getting Started](#getting-started)
- [Tutorial](#tutorial)
- [Architecture Guide](#architecture-guide)
- [Advanced Features](#advanced-features)
- [Performance & Optimization](#performance--optimization)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Getting Started

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/aua.git
cd aua

# Install dependencies
bundle install

# Run the REPL
bin/aura

# Run a program
bin/aura examples/hello.aura
```

### Development Environment

#### VS Code Setup

1. Install the Ruby extension
2. Configure Steep for type checking:
   ```bash
   bundle exec steep check
   ```

#### Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/aua/features/function_definitions_spec.rb

# Run with coverage
bundle exec rspec --format documentation
```

## Tutorial

### Hello World

```aura
say "Hello, World!"
```

### Variables and Basic Types

```aura
# Numbers
age = 25
height = 5.9

# Strings
name = "Alice"
greeting = "Hello, ${name}!"

# Booleans
is_student = true
is_adult = age >= 18

# Collections
hobbies = ["reading", "coding", "hiking"]
person = { name: "Bob", age: 30 }
```

### Functions

```aura
# Define a function
fun add(x, y)
  x + y
end

# Call the function
result = add(5, 3)
say result  # 8

# Lambda expressions
double = x => x * 2
triple = (x) => x * 3

# Higher-order functions
numbers = [1, 2, 3, 4, 5]
doubled = numbers.map(double)
say doubled  # [2, 4, 6, 8, 10]
```

### Control Flow

```aura
# Conditionals
score = 85
if score >= 90
  grade = "A"
elif score >= 80
  grade = "B"
else
  grade = "C"
end

# Loops
count = 0
while count < 5
  say "Count: ${count}"
  count = count + 1
end
```

### Working with Objects

```aura
# Create an object
person = {
  name: "Charlie",
  age: 28,
  city: "Portland"
}

# Access fields
say person.name    # "Charlie"

# Update fields (functional style)
person.age = 29    # Creates new object

# Method calls (when available)
description = person.toString()
```

### AI-Powered Features

```aura
# Generative strings
story = """Write a short story about a robot learning to paint"""

# Structured generation
interface Recipe
  name: String
  ingredients: Array[String]
  instructions: Array[String]
  cooking_time: Int
end

dinner_recipe = """Create a recipe for pasta carbonara""" as Recipe

# Type casting with AI
user_input = ask "Enter your favorite color"
color_code = user_input as HexColor  # AI converts to hex

# Semantic operations
is_similar = "happy" ~= "joyful"     # true
best_choice = "I want dessert" ~ ["cake", "salad", "soup"]  # "cake"
```

## Architecture Guide

### Overview

Aua's architecture consists of several key components working together:

```
Source Code → Lexer → Parser → AST → Translator → VM → Result
              ↓       ↓       ↓       ↓         ↓
           Tokens   AST    Instructions  Execution
```

### Component Details

#### Lexer (`lib/aua/lex.rb`)

- **Purpose**: Convert source code into tokens
- **Key Features**:
  - Context-aware string interpolation
  - Operator recognition
  - Error reporting with source positions
- **Extension Points**: Add new token types in `lib/aua/syntax.rb`

#### Parser (`lib/aua/parse.rb`)

- **Purpose**: Build Abstract Syntax Tree from tokens
- **Key Features**:
  - Recursive descent parsing
  - Operator precedence handling
  - Grammar modules for extensibility
- **Extension Points**: Add new grammar rules in `lib/aua/grammar.rb`

#### Virtual Machine (`lib/aua/runtime/vm.rb`)

- **Purpose**: Execute AST instructions
- **Key Features**:
  - Environment management
  - Function call stack
  - Built-in function integration
- **Extension Points**: Add new built-ins in the `builtins` method

#### Type System (`lib/aua/runtime/type_registry.rb`)

- **Purpose**: Manage types and casting
- **Key Features**:
  - Dynamic type checking
  - AI-powered universal casting
  - User-defined types
- **Extension Points**: Register new types via the TypeRegistry

### Adding New Features

#### New Built-in Function

```ruby
# In lib/aua/runtime/vm.rb
def builtin_your_function(arg)
  # Implementation
  result = process(arg)
  Aua::YourType.new(result)
end

# Register in builtins hash
def builtins
  @builtins ||= {
    # ... existing builtins
    your_function: method(:builtin_your_function)
  }
end
```

#### New Operator

```ruby
# 1. Add to lexer (lib/aua/syntax.rb)
TWO_CHAR_TOKEN_NAMES = {
  # ... existing tokens
  "@@" => :your_op
}

# 2. Add precedence (lib/aua/grammar.rb)
BINARY_PRECEDENCE = {
  # ... existing operators
  your_op: 6  # Choose appropriate precedence
}

# 3. Add translation (lib/aua/runtime/vm/translator.rb)
def binary_operation(operator, left, right)
  case operator
  # ... existing cases
  when :your_op then handle_your_operation(left, right)
  end
end
```

#### New Type

```ruby
# In lib/aua/obj.rb
class YourType < Obj
  def initialize(value)
    super()
    @value = value
  end

  def introspect
    "YourType(#{@value})"
  end

  def self.json_schema
    {
      type: "object",
      properties: {
        value: { type: "string" }
      }
    }
  end
end
```

## Advanced Features

### Closures and Environment Capture

```aura
fun make_accumulator(initial)
  total = initial
  (value) => {
    total = total + value
    total
  }
end

acc = make_accumulator(10)
acc(5)   # 15
acc(3)   # 18
```

### Metaprogramming with AST Nodes

```aura
# Future feature - manipulate code as data
code = parse("x + y")
modified = code.replace("x", "z")
result = eval(modified)
```

### Custom Types and Schemas

```aura
# Define complex types
type Color = "red" | "green" | "blue" | HexColor
type HexColor = /^#[0-9A-Fa-f]{6}$/

# Use in AI casting
user_color = ask "What's your favorite color?"
color = user_color as Color  # Validates against union
```

### Performance Optimization Strategies

#### Caching AI Responses

The LLM provider automatically caches responses:

```ruby
# Responses are cached by prompt + schema hash
# Repeated calls with same input are instant
result1 = """Generate a story""" as Story
result2 = """Generate a story""" as Story  # Cache hit
```

#### Optimizing Function Calls

```aura
# Avoid creating new lambdas in loops
double = x => x * 2  # Create once
numbers.map(double)  # Reuse

# Instead of:
# numbers.map(x => x * 2)  # Creates new lambda each time
```

## Performance & Optimization

### Current Performance Characteristics

- **Interpretation**: Aua is currently interpreted, not compiled
- **Memory**: Uses Ruby's garbage collection
- **AI Calls**: Cached to avoid repeated LLM requests
- **Function Calls**: Stack-based with overflow protection

### Optimization Guidelines

#### Minimize AI Calls

```aura
# Good: Cache results
response = """Generate data""" as DataType
process_multiple_times(response)

# Avoid: Repeated generation
# process("""Generate data""" as DataType)
# process("""Generate data""" as DataType)  # Same call twice
```

#### Efficient Object Updates

```aura
# Functional updates create new objects
person = { name: "Alice", age: 30 }
person.age = 31     # Creates new object
person.city = "NY"  # Creates another new object

# Better: Update multiple fields together
person = person.update({ age: 31, city: "NY" })  # Future feature
```

### Future Optimizations

- **Bytecode Compilation**: Planned compilation to intermediate representation
- **Type Inference**: Static analysis to eliminate runtime type checks
- **SSA Form**: Single Static Assignment for optimization passes
- **JIT Compilation**: Just-in-time compilation for hot code paths

## Troubleshooting

### Common Errors

#### Parse Errors

```
Error: Unexpected token 'if' at line 5, column 10
```

**Solution**: Check for missing `end` keywords or unmatched parentheses.

#### Type Errors

```
Error: Cannot add Str and Int
```

**Solution**: Use explicit casting: `"5" as Int + 10`

#### Undefined Variable

```
Error: Undefined variable: 'undeclared_var'
```

**Solution**: Ensure variable is declared before use.

#### Function Arity Errors

```
Error: Function 'add' expects 2 arguments, got 1
```

**Solution**: Check function signature and provide correct number of arguments.

### Debugging Techniques

#### Enable Debug Logging

```bash
AURA_DEBUG=true bin/aura your_program.aura
```

#### Inspect Objects

```aura
person = { name: "Alice" }
say inspect(person)  # Shows internal representation
```

#### Step-by-step Execution

```aura
# Add logging statements
say "About to call function"
result = my_function(arg)
say "Function returned: ${inspect(result)}"
```

### Performance Issues

#### Slow AI Responses

- **Cause**: Network latency to LLM provider
- **Solution**: Use caching, optimize prompts, consider local models

#### Memory Usage

- **Cause**: Large object graphs, circular references
- **Solution**: Use smaller objects, avoid deep nesting

#### Stack Overflow

- **Cause**: Infinite recursion
- **Solution**: Add base cases, use iteration where possible

## Contributing

### Development Setup

```bash
# Fork and clone
git clone https://github.com/yourusername/aua.git
cd aua

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Type checking
bundle exec steep check
```

### Code Style

- Follow Ruby style conventions
- Use meaningful variable names
- Write comprehensive tests
- Document new features

### Testing Guidelines

```ruby
# Feature tests
RSpec.describe "New Feature" do
  it "handles basic case" do
    expect("code").to be_aua(expected_result)
  end

  it "handles edge cases" do
    expect { "invalid code" }.to raise_aura(/error pattern/)
  end
end
```

### Adding Documentation

- Update language reference for new syntax
- Add examples to manual
- Update README with feature summary
- Consider adding tutorials for complex features

### Submitting Changes

1. Create feature branch
2. Write tests first (TDD)
3. Implement feature
4. Update documentation
5. Submit pull request with clear description

### Architecture Decisions

When adding major features, consider:

- **Backwards Compatibility**: Don't break existing code
- **Performance Impact**: Profile before and after
- **AI Integration**: How does it work with LLM features?
- **Type Safety**: Can types be inferred or checked?
- **Extensibility**: Can users build on this feature?
