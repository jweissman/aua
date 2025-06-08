# Aua (Aura-lang)

Aua (Aura-lang + u + Agent) is a metacircular, agentic programming language and runtime platform designed for human-first, AI-native computing. It fuses code, cognition, and collaboration into an interactive language runtime and epistemic assistant environment, grounded in structured data and interpretable actions. Aua is a foundation for building autonomous toolmakers, semiotic gardens, and reflective knowledge interfaces.

## Vision

Where we're going, we don't need prose — now generative structure, plans, and tools are typed data.

🪞 Introspective

*Aura aspires to be self-hosting and reflexive, allowing the language and its tools to evolve from within.*

🦾 Self-improving

*The agent can write new Aura programs (“gadgets”) in response to prompts, which are versioned, auditable, and reusable.*

🦄 Self-limiting

*The system improves by building on itself, with user supervision and trust signals.*

👁️ Observable

*Every agent action is inspectable, reasoned about, and refinable.*

🤷‍♂️ Language Model Runtime

*A persistent agent watches generative evaluations, tracks completions, and suggests optimizations. All completions are auditable and can be reviewed, replayed, or blessed by the user.*

Aura is for users who want to build, audit, and evolve their own tools.

## Key Features
### Generative Casting and Prompt Literals
- **Prompt as Code:** Triple-quoted string literals (`""" ... """`) are evaluated as prompts to a language model (LLM) at runtime. They are also first-class citizens in the language -- not only can they be modified and extended at runtime, but they can be composed into a multi-shot workflow which in turn is just an object too.
- **Generative Casting:** Aura provides structured, type-safe LLM completions in a general programming context. Any object may be cast to an object of any other type using the generative agent. In particular, the result of a generative literal can be cast to any Aura type, using schema-guided parsing and validation. 

  ```aura
  interface Reason
    answer: String
    the_REAL_answer: String
    narrative: String
    metaphor: String
  end

  reasoning = """Why is the sky blue?""" as Reason
  decision_point = answer ~|- the_REAL_answer

  value_function = """Which is more interesting?""" 
  actual_response = decision_point |- value_function
  say actual_response
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