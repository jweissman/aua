# Aua Language Reference

## Table of Contents

- [Syntax Overview](#syntax-overview)
- [Lexical Structure](#lexical-structure)
- [Types](#types)
- [Operators](#operators)
- [Control Flow](#control-flow)
- [Functions](#functions)
- [Objects & Members](#objects--members)
- [Type System](#type-system)
- [AI Integration](#ai-integration)
- [Built-in Functions](#built-in-functions)

## Syntax Overview

Aua uses a clean, expression-oriented syntax designed for both human readability and AI interaction. Every construct in Aua is an expression that evaluates to a value.

### Basic Structure

```aura
# Comments start with #
statement1
statement2
# Semicolons are optional but can be used for clarity
x = 42; y = 24
```

## Lexical Structure

### Identifiers

```aura
simple_name
camelCase
PascalCase
with_underscores
name123
```

### Keywords

```
if elif else end
while
fun
type interface
true false nihil
as
```

### Literals

#### Numbers

```aura
42          # Int
3.14        # Float
-17         # Negative Int
-2.5        # Negative Float
```

#### Strings

```aura
"simple string"
'also a string'
"string with ${variable} interpolation"
"""
Multi-line generative string
that gets processed by AI
"""
```

#### Collections

```aura
[1, 2, 3]                    # Array
{ name: "Alice", age: 30 }   # Object literal
```

## Types

### Primitive Types

#### `Int`

Integer numbers with arbitrary precision.

```aura
x = 42
y = -17
big = 999999999999999999
```

#### `Float`

Floating-point numbers.

```aura
pi = 3.14159
temp = -40.5
```

#### `Bool`

Boolean true/false values.

```aura
flag = true
done = false
```

#### `Str`

Unicode strings with interpolation support.

```aura
name = "Alice"
greeting = "Hello, ${name}!"
```

#### `Nihil`

Represents absence of value (null/void).

```aura
result = nihil
```

### Collection Types

#### `List`

Ordered collections of values.

```aura
numbers = [1, 2, 3]
mixed = ["hello", 42, true]
empty = []
```

#### `Object`

Key-value dictionaries.

```aura
person = {
  name: "Bob",
  age: 25,
  active: true
}
```

### Function Types

Functions are first-class values.

```aura
# Named function
fun square(x)
  x * x
end

# Lambda expressions
double = x => x * 2
add = (a, b) => a + b
```

## Operators

### Arithmetic

```aura
x + y    # Addition
x - y    # Subtraction
x * y    # Multiplication
x / y    # Division
x ** y   # Exponentiation
-x       # Negation
```

### Comparison

```aura
x == y   # Equality
x != y   # Inequality
x < y    # Less than
x > y    # Greater than
x <= y   # Less than or equal
x >= y   # Greater than or equal
```

### Logical

```aura
x && y   # Logical AND
x || y   # Logical OR
!x       # Logical NOT
```

### Assignment

```aura
x = 42          # Variable assignment
obj.field = val # Member assignment
```

### Special Operators

#### Type Casting (`as`)

```aura
number = "42" as Int
text = 123 as Str
```

#### Barred Union (`~`)

Neurosymbolic operator for semantic selection and blending.

```aura
# Semantic equivalence
"hello" ~= "hi"

# Selection from choices
answer = question ~ ["yes", "no", "maybe"]

# Conceptual blending
style = "modern" ~ "vintage"
```

#### Member Access (`.`)

```aura
person.name       # Get field
person.age = 25   # Set field
obj.method()      # Call method
```

#### Lambda (`=>`)

```aura
square = x => x * x
add = (x, y) => x + y
```

### Operator Precedence

From highest to lowest:

1. `.` (member access)
2. `**` (exponentiation)
3. `*`, `/` (multiplication, division)
4. `+`, `-` (addition, subtraction)
5. `==`, `!=`, `<`, `>`, `<=`, `>=` (comparison)
6. `&&` (logical AND)
7. `||` (logical OR)
8. `~` (barred union)
9. `as` (type casting)
10. `=>` (lambda)
11. `=` (assignment)

## Control Flow

### Conditionals

```aura
# Basic if-else
if condition
  action1
else
  action2
end

# Multi-branch
if score >= 90
  grade = "A"
elif score >= 80
  grade = "B"
elif score >= 70
  grade = "C"
else
  grade = "F"
end

# Ternary-style (single expression)
if condition then value1 else value2
```

### Loops

```aura
# While loop
while count < 10
  say count
  count = count + 1
end
```

## Functions

### Function Definitions

```aura
# Basic function
fun greet(name)
  "Hello, ${name}!"
end

# Function with multiple parameters
fun calculate(x, y, operation)
  if operation == "add"
    x + y
  elif operation == "multiply"
    x * y
  else
    nihil
  end
end
```

### Lambda Expressions

```aura
# Single parameter
square = x => x * x

# Multiple parameters
add = (x, y) => x + y

# No parameters
random = () => rand(100)

# Block body (multiline)
complex = (data) => {
  processed = data.clean()
  result = processed.transform()
  result.validate()
}
```

### Higher-Order Functions

```aura
# Functions as arguments
numbers = [1, 2, 3, 4, 5]
doubled = numbers.map(x => x * 2)

# Functions returning functions
fun make_multiplier(factor)
  x => x * factor
end

times_three = make_multiplier(3)
result = times_three(7)  # 21
```

### Closures

Functions capture their lexical environment:

```aura
fun make_counter()
  count = 0
  () => {
    count = count + 1
    count
  }
end

counter = make_counter()
counter()  # 1
counter()  # 2
```

## Objects & Members

### Object Literals

```aura
person = {
  name: "Alice",
  age: 30,
  active: true
}
```

### Member Access

```aura
# Get field
name = person.name

# Set field (creates new object)
person.age = 31

# Method calls (when supported)
person.toString()
```

### Mutability Semantics

Aua uses functional-style updating for object members:

```aura
original = { x: 10, y: 20 }
modified = original.x = 15  # Creates new object
# original still has x: 10
# modified has x: 15, y: 20
```

## Type System

### Type Declarations

```aura
# Union types
type Status = "active" | "inactive" | "pending"

# Interface definitions (planned)
interface Person
  name: String
  age: Int
  active: Bool
end
```

### Type Casting

```aura
# Basic casting
number = "42" as Int
text = 123 as Str

# AI-powered universal casting
weather_data = {
  temp: "hot",
  humidity: "high",
  conditions: "sunny"
}
weather = weather_data as WeatherReport
```

## AI Integration

### Generative Strings

Triple-quoted strings are evaluated by language models:

```aura
# Simple generation
description = """Describe a cozy coffee shop"""

# With context
context = "medieval fantasy setting"
character = """Create a character description for ${context}"""
```

### Structured Generation

Use type schemas to guide AI output:

```aura
interface Character
  name: String
  class: String
  level: Int
  backstory: String
end

hero = """Create a heroic character""" as Character
# Returns structured Character object
```

### Semantic Operations

The `~` operator enables AI-mediated operations:

```aura
# Semantic comparison
"happy" ~= "joyful"     # true
"red" ~= "crimson"      # true

# Choice selection
user_intent = "I want something sweet"
recommendation = user_intent ~ ["cake", "salad", "pizza"]
# Returns "cake"

# Conceptual blending
style = "baroque" ~ "minimalist"
# Returns AI-mediated fusion
```

## Built-in Functions

### I/O Functions

```aura
say "Hello"              # Print to stdout
name = ask "Your name?"  # Read from stdin
```

### Utility Functions

```aura
inspect obj              # Debug representation
rand 100                 # Random number 0-99
time                     # Current time
```

### AI Functions

```aura
chat "What is AI?"       # Chat with language model
see_url "https://..."    # Fetch and process URL
cast obj Type            # AI-powered type conversion
```

### Type Functions

```aura
typeof obj               # Get object type (planned)
```

## Error Handling

Aua uses runtime error reporting with source location tracking:

```aura
# Type errors
x = "hello" + 42         # Error: cannot add Str and Int

# Undefined variables
y = undefined_var        # Error: variable not found

# Function arity errors
fun add(x, y) x + y end
add(1)                   # Error: wrong number of arguments
```

## Future Features

### Pattern Matching (Planned)

```aura
match value
  when "yes" then true
  when "no" then false
  when _ then nihil
end
```

### Generic Types (Planned)

```aura
type List[T] = Array[T]
type Result[T, E] = Success[T] | Error[E]
```

### Method Definitions (Planned)

```aura
class Person
  def initialize(name, age)
    @name = name
    @age = age
  end

  def greet()
    "Hello, I'm ${@name}"
  end
end
```
