---
name: elm-patterns
description: Apply idiomatic Elm patterns when writing or reviewing Elm code. Use when working on Elm files, modeling data in Elm, designing module or package APIs (argument order, naming, opaque types, documentation), reviewing a package's public API, structuring TEA applications (Model/Msg/update/view), handling parent-child communication, or when the user mentions custom types, Maybe, Result, decoders, opaque types, phantom types, impossible states, boolean blindness, or testing update functions.
license: Content adapted from https://github.com/sporto/elm-patterns by Sebastian Porto, and from the Elm package design guidelines
metadata:
  source: https://sporto.github.io/elm-patterns/
  upstream-author: sporto
  api-design-source: https://package.elm-lang.org/help/design-guidelines
---

# Elm Patterns

Idiomatic patterns for Elm, adapted from [Elm Patterns](https://sporto.github.io/elm-patterns/) by Sebastian Porto, plus public API design guidance from the [Elm package design guidelines](https://package.elm-lang.org/help/design-guidelines).

## Core principles

Lean on the compiler. Most patterns here are ways to move guarantees from runtime discipline into types:

1. **Make impossible states impossible.** If two fields must stay in sync, replace them with one custom type whose variants are exactly the valid states.
2. **Prefer custom types over primitives and booleans.** A `Bool` or bare `String`/`Float` argument hides intent and lets values get mixed up.
3. **Parse, don't validate.** Convert loose boundary data (user input, JSON) into a distinct known-valid type; don't check and keep the loose type.
4. **Wrap early, unwrap late** for domain values; **unwrap `Maybe`/`Result` early** in views so children take plain values.
5. **Keep views as plain functions.** Reach for nested TEA only at page level, sparingly.
6. **Design public APIs from call sites.** Start from realistic usage, put the primary data structure last, keep package-owned types opaque, and name functions to read well when qualified (`Parser.parse`, not `Parser.parseParser`).

## Pattern index

Match the symptom to a pattern, then read that section in the reference file.

### Data modeling and API design → [references/basic-patterns.md](references/basic-patterns.md)

| Pattern | Use when |
|---|---|
| Type blindness | Same-typed values (two `String`s, two `Float`s) could be mixed up |
| Minimize boolean usage | `Bool` argument unclear at call site, or `Bool` return feeds an `if` |
| Named arguments | Positional arguments of the same type are ambiguous |
| Wrap early, unwrap late | Wrapper types exist but functions still pass primitives around |
| Unwrap Maybe early | Views/helpers keep re-unwrapping the same `Maybe`/`Result` |
| Make impossible states impossible | Model fields allow contradictory combinations (`isLoading` + `Maybe data`) |
| Parse, don't validate | Boundary data checked with `isValid : x -> Bool` but type stays loose |
| Builder pattern | Function takes a large args record; adding a field breaks all callers |
| Arguments list | Configuration where every setting is optional (elm/html style) |
| Type iterator | A list of all variants of a custom type can go stale |
| Conditional rendering | An element should render only sometimes |

### Type-system techniques → [references/advanced-patterns.md](references/advanced-patterns.md)

| Pattern | Use when |
|---|---|
| Railway | Chaining steps that each return `Result`/`Maybe` (or need early exit) |
| Pipeline builder | Building a record via piped fallible steps (decoders, validation) |
| Opaque types | Hiding a type's internals so the module can evolve without breaking callers |
| Opaque types for invariants | Data must always satisfy a rule (e.g. always sorted) |
| Combinators | Values of a type should compose into the same type (trees, filters, decoders) |
| Phantom types | Compiler should track evidence (validated, filtered, unit) without runtime cost |
| Process flow with phantom types | Multi-step process must run in order with no skipped steps |

### Package and module API design → [references/package-api-design.md](references/package-api-design.md)

| Guideline | Use when |
|---|---|
| Start from a concrete use case | Designing a new package/module, or an API has no realistic example justifying it |
| Avoid gratuitous abstraction | Type parameters, config layers, or indirection without a demonstrated user benefit |
| Design documentation alongside the API | Public functions lack docs/examples, or docs follow implementation order |
| Put the data structure last | Pipelines or folds need `flip`/lambdas to use a function |
| Keep constructors private | `exposing (Type(..))` or a public type alias for package-owned data |
| Opaque types for evolving domain concepts | `type alias UserId = String` for a concept the package owns |
| Human-readable names | Abbreviated names (`cfg`, `maxAtt`, `prev`) in a public API |
| Don't repeat the module name | Qualified calls stutter (`Config.emptyConfig`) |
| Design for qualified imports / call-site readability | API only reads well with `exposing (..)`, or call sites are awkward |
| Design workflow + review checklist | Designing a package end-to-end, or reviewing a package's public API |

### TEA application structure → [references/architecture-patterns.md](references/architecture-patterns.md)

| Pattern | Use when |
|---|---|
| Reusable views | A reusable "component" — try a plain view function before nested TEA |
| Nested TEA | A page needs its own Model/Msg/update loop |
| Child outcome | Child update must notify its parent something happened |
| Translator | Child view must emit messages destined for the parent |
| Global actions | Deeply nested modules trigger app-level behavior (notifications, sign-out) |
| Effects pattern | `update` returning opaque `Cmd` makes tests impossible |
| Update return pipeline | One update branch does many things and grows complex |

## How to apply

1. When writing new Elm code, check the model against principle 1 before adding fields; check function signatures against principles 2–4.
2. When reviewing Elm code, scan for the symptoms in the tables above and cite the matching pattern.
3. When designing or reviewing a package or shared module's public API, follow the workflow and checklist in [references/package-api-design.md](references/package-api-design.md); report each finding as current API → effect on user code → improved API → resulting call site → why it's better.
4. Read only the reference file section you need; each entry has the problem, the pattern, a code example, and a link to its source.
