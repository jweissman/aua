# Aua (Aura-lang)

Aua (Aura-lang + u + Agent) is a metacircular, agentic programming language and runtime platform designed for human-first, AI-native computing. It fuses code, cognition, and collaboration into an interactive language runtime and epistemic assistant environment, grounded in structured data and interpretable actions. Aua is a foundation for building autonomous toolmakers, semiotic gardens, and reflective knowledge interfaces.

## Vision

Where we're going, we don't need prose — now generative structure, plans, and tools are typed data.

🪞 Introspective

_Aura aspires to be self-hosting and reflexive, allowing the language and its tools to evolve from within._

🦾 Self-improving

_The agent can write new Aura programs (“gadgets”) in response to prompts, which are versioned, auditable, and reusable._

🦄 Self-limiting

_The system improves by building on itself, with user supervision and trust signals._

👁️ Observable

_Every agent action is inspectable, reasoned about, and refinable._

🤷‍♂️ Language Model Runtime

_A persistent agent watches generative evaluations, tracks completions, and suggests optimizations. All completions are auditable and can be reviewed, replayed, or blessed by the user._

Aura is for users who want to build, audit, and evolve their own tools.

## Architecture Overview

Aua features a clean, modular architecture built around these core verticals:

### 🔤 **Lexical Analysis & Parsing**

- **Contextual Lexer**: Token-stream generation with support for string interpolation, object literals, and context-aware parsing
- **Recursive Descent Parser**: AST construction with operator precedence, lambda expressions, and unified assignment model
- **Grammar System**: Modular grammar definitions with extensible primitive parsing

### ⚙️ **Virtual Machine & Runtime**

- **Stack-Based VM**: Environment management, function calls, and instruction execution
- **AST Translator**: Converts parse trees to executable VM instructions
- **Statement System**: Unified instruction representation for type-safe execution

### 🏷️ **Type System & Objects**

- **Dynamic Typing**: Runtime type checking with AI-powered universal type casting
- **Object Model**: First-class functions, closures, object literals, and member access
- **Type Registry**: Custom type definitions, unions, and schema generation

### 🤖 **AI Integration**

- **LLM Provider**: Configurable AI model integration with caching and error handling
- **Generative Casting**: Schema-guided type conversion using language models
- **Universal Typecasting**: Transform any object into any other type via AI reasoning

## Key Features

### Language Syntax & Features

#### **Basic Types & Literals**

```aura
# Primitives
x = 42                    # Int
y = 3.14                  # Float
flag = true               # Bool
name = "Alice"            # Str
nothing = nihil           # Nihil (null/void)

# String interpolation
greeting = "Hello, ${name}!"

# Arrays and objects
numbers = [1, 2, 3]
person = { name: "Bob", age: 30 }
```

#### **Functions & Lambdas**

```aura
# Named functions
fun add(x, y)
  x + y
end

# Lambda expressions (multiple forms)
double = x => x * 2
multiply = (x, y) => x * y
process = () => say "Processing..."

# Higher-order functions
numbers.map(double)
```

#### **Control Flow**

```aura
# Conditionals
if age >= 18
  say "Adult"
elif age >= 13
  say "Teenager"
else
  say "Child"
end

# Loops
while count < 10
  count = count + 1
end
```

#### **Object-Oriented Features**

```aura
# Object member access and assignment
person.age = 31
person.name = "Robert"
result = person.dup()
```

#### **Type System**

```aura
# Type declarations
type Status = "active" | "inactive" | "pending"

# Type casting with AI
user_input = ask "Enter a number"
number = user_input as Int

# Universal typecasting (AI-powered)
data = { temperature: "hot", humidity: "high" }
weather = data as WeatherReading
```

#### **Generative Casting and Prompt Literals**

- **Prompt as Code:** Triple-quoted string literals (`""" ... """`) are evaluated as prompts to a language model (LLM) at runtime. They are also first-class citizens in the language -- not only can they be modified and extended at runtime, but they can be composed into a multi-shot workflow which in turn is just an object too.
- **Generative Casting:** Aura provides structured, type-safe LLM completions in a general programming context. Any object may be cast to an object of any other type using the generative agent. In particular, the result of a generative literal can be cast to any Aura type, using schema-guided parsing and validation.

```aura
# Generative literals - AI-powered string generation
description = """Describe a mysterious forest clearing"""

# Structured generation with type schemas
interface Reason
  answer: String
  the_REAL_answer: String
  narrative: String
  metaphor: String
end

reasoning = """Why is the sky blue?""" as Reason
decision_point = reasoning.answer ~ reasoning.the_REAL_answer

# Barred union operator for superposition/selection
value_function = """Which is more interesting?"""
actual_response = decision_point ~ value_function
say actual_response
```

#### **Neurosymbolic Operators**

Aua pioneeres "barred union" semantics with the `~` (tilde) operator, enabling gradual resolution of superposed values:

```aura
# Fuzzy/semantic comparison
"Hello" ~= "Hi"           # true (semantic equivalence)
"cats" ~= "felines"       # true (conceptual match)

# Semantic selection from unions
answer = user_question ~ ["yes", "no", "maybe"]

# Conceptual blending/composition
style = "gothic" ~ "minimalist"  # AI-mediated style fusion
```

In fact casts can be between any two objects with a reified schema (arrays, graphs, records, etc).

### Type System

- Aura supports primitive types (Int, Float, Bool, Str, Nihil), records, and user-defined interfaces.
- Generative completions are parsed and validated against the expected type’s schema, with support for shallow recursion and manual resolution for complex types.
- Any object of any type may be flexibly and forgivingly cast to any known Aura type:
  - Primitive types (String, Bool, Int, etc.)
  - JSON/structured records (Hash, Array)
  - User-defined types (struct, enum, more complex types via interface and type algebra etc.)
  - AST Nodes: Full parseable syntax trees with runtime evaluation hooks

### Interface & Auditability

- Chat + code prompt interface, with a feed of structured entries (code, posts, ideas, etc.), each with a backing schema and audit trail.
- AST viewer, trace viewer, and trust/bless/flag mechanisms for agentic suggestions.

## Quickstart

Install dependencies and run the Aura REPL or a sample program:

```sh
bundle install
bin/console
```

Try evaluating a generative string literal:

```aura
"""Why is the sky blue?"""
```

This will invoke the configured language model and return a string (e.g., mentioning "Rayleigh scattering").

## Current Status

- ✅ Core language: literals, arithmetic, variables, control flow, error handling
- ✅ Generative string literals (triple-quoted, LLM-backed)
- ⏳ Generative casting to structured types (planned, partial support)
- ⏳ Agentic runtime, tool-writing, and self-improvement (planned)
- ⏳ Web interface and visualization tools (planned)

See `spec/aua_spec.rb` for the current test suite and language features. Type signatures are defined in `sig/aua.rbs`.

## Contributing

- To add a new feature, write a spec first, then implement and verify.
- Contributions to the type system, generative casting, and agentic runtime are especially welcome.

---

## Roadmap

- Implement generative casting: parse/cast LLM completions to expected Aura types using schema from the type system.
- Integrate with local LLM backends (e.g., Ollama) for development and testing.
- Expand agentic features: persistent memory, tool-writing, and self-improvement.
- Build web-based workspace and visualization tools.

### Medium-Term Goals

- Define Aura’s minimal type system and AST schema
- Build prototype agent loop with generative literals + casting
- Design minimal UI for displaying completions and traces
- Add persistent tool writing + blessing
- Add command runner backend + task definitions
- Document metacircular bootstrapping path
