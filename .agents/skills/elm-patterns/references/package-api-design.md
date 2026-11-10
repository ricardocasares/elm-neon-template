# Elm Package API Design

Guidelines for designing, implementing, refactoring, or reviewing the public API of an Elm package or shared module. Adapted from the [Elm package design guidelines](https://package.elm-lang.org/help/design-guidelines).

The goal: APIs that are concrete, readable, composable, stable, and easy to learn — optimized for clarity at the call site and flexibility behind the module boundary.

## Priorities

When making API decisions, prioritize, in order:

1. A concrete user problem
2. Simplicity over abstraction
3. Clear examples and documentation
4. Consistent argument ordering
5. Encapsulation and API stability
6. Human-readable naming
7. Namespaced APIs

Do not optimize for theoretical generality unless it produces a concrete improvement for users.

## Start from a concrete use case

**Problem:** APIs designed from abstract type machinery first, with a use case found afterward, end up general but awkward for the people who actually use them.

**Guideline:** Before implementing, establish:

- What concrete problem does this package solve, and who has it?
- What would a successful API let them write?
- What are the most common operations, and what does the simplest realistic usage look like?
- What existing packages solve similar problems, and which of their weaknesses should this API avoid?

Write realistic example usage *before* settling on types, and let it shape the API:

```elm
result =
    input
        |> Parser.parse
        |> Result.map transform
```

**Review rule:** If an abstraction or public function cannot be justified by a realistic usage example, question whether it belongs in the public API.

## Avoid gratuitous abstraction

**Problem:** Making an API more general because the type system allows it adds concepts users must learn without making their code better.

**Guideline:** Abstraction is a tool, not a goal. Prefer

```elm
parse : String -> Result Error Document
```

over a highly generic abstraction unless the extra generality solves demonstrated user problems. Before adding abstraction, ask whether it:

- is required by a concrete use case
- makes common code shorter or clearer
- removes duplication users would otherwise hit
- improves composition
- makes the package easier to extend without complicating normal usage

If the benefit cannot be demonstrated with code, prefer the simpler API. Avoid:

- type parameters without a concrete need
- generalized configuration layers for hypothetical future requirements
- custom abstractions over concepts Elm already expresses clearly
- indirection that only reduces *implementation* duplication while worsening the public API

Internal abstraction is far less concerning than public abstraction. Optimize the public API for users, not implementation cleverness.

## Design documentation alongside the API

**Problem:** A function that can only be understood by reading its implementation isn't finished.

**Guideline:** Every public function's docs should explain what it does, the meaning of important arguments, important behavior and edge cases, and — when useful — a representative example of *normal* usage (not an artificial one). Important modules get a module-level example showing several functions working together:

```elm
config =
    Config.empty
        |> Config.withTimeout 5000
        |> Config.withRetries 3
```

**Documentation order is API design.** Organize functions in the order a new user would encounter them, under meaningful section names — never just implementation order. A typical ordering:

1. Core type
2. Constructors
3. Basic operations
4. Query functions
5. Transformations
6. Advanced operations
7. Conversion or interoperability helpers

## Put the data structure last

**Problem:** When the primary data structure isn't the last argument, pipelines and folds need `flip` or lambdas.

**Guideline:** For functions shaped like `operation(parameters..., data)`, the data argument goes last:

```elm
remove : String -> Dict String value -> Dict String value

insert : Key -> Value -> Dict Key Value -> Dict Key Value

setWidth : Int -> Layout -> Layout

map : (a -> b) -> Collection a -> Collection b

filter : (a -> Bool) -> Collection a -> Collection a
```

so callers can write:

```elm
people
    |> Dict.remove "Steve"
```

and folds compose directly. Compare:

```elm
-- data first: needs an adapter
without : Dict String value -> String -> Dict String value

foldr (flip without) people names

-- data last: composes as-is
remove : String -> Dict String value -> Dict String value

foldr remove people names
```

The improvement is not merely stylistic; argument order determines composability.

**Exceptions:** Don't apply this mechanically when there is no obvious primary data structure — `compare : a -> a -> Order` has symmetric arguments. Use semantic judgment, but strongly prefer data-last for operations over package types. (When same-typed arguments are genuinely ambiguous, see *Named arguments* in [basic-patterns.md](basic-patterns.md).)

## Keep constructors private

**Problem:** Exposing a constructor (`exposing (Point(..))`) or a type alias for package-owned data lets users construct, inspect, and depend on the representation. Any internal change becomes a breaking change.

```elm
-- Avoid for package-owned concepts: representation is public
type alias Point =
    { x : Float
    , y : Float
    }
```

**Guideline:** Expose the type, not its constructor, and provide construction and inspection functions:

```elm
module Point exposing
    ( Point
    , fromXY
    , x
    , y
    )

type Point
    = Point
        { x : Float
        , y : Float
        }

fromXY : Float -> Float -> Point

x : Point -> Float

y : Point -> Float
```

The implementation can later switch to polar coordinates, add a third dimension, normalize values, cache metadata, or add record fields without changing the public API.

Expose constructors only when users genuinely need to pattern match on all variants as part of the intended API. See also *Opaque types* in [advanced-patterns.md](advanced-patterns.md).

## Opaque types for evolving domain concepts

**Problem:** `type alias UserId = String` lets any string be a `UserId` and ties users to the representation.

**Guideline:** Use an opaque type — even with a single constructor — when the package owns the semantics:

```elm
type UserId
    = UserId String

fromString : String -> Maybe UserId

toString : UserId -> String
```

Appropriate when the representation may change, the value has invariants, construction should be controlled, users shouldn't depend on internal fields, or internal information may be added later.

**Don't** introduce opaque wrappers merely for ceremony. They should protect a meaningful domain boundary or future implementation freedom.

## Prefer human-readable names

**Problem:** Abbreviations save keystrokes for the author and cost comprehension for every reader.

**Guideline:** Prefer `maximumAttempts` over `maxAtt`, `configuration` over `cfg`, `previous` over `prev` when the longer form materially improves clarity. Avoid abbreviations unless universally understood in the problem domain.

Short names are fine when already conventional and unambiguous: `map`, `filter`, `foldl`, `get`, `set`. Do not shorten names merely to reduce typing — API clarity beats saving characters.

## Don't repeat the module name

**Problem:** The module is already a namespace; repeating it makes qualified calls stutter.

**Guideline:** Assume users call functions qualified by module name, and design names so qualified usage reads naturally:

| Good | Bad |
|---|---|
| `State.run` | `State.runState` |
| `Parser.parse` | `Parser.parseParser` |
| `Config.empty` | `Config.emptyConfig` |
| `Point.fromXY`, `Point.x` | `Point.pointFromXY`, `Point.pointX` |
| `Request.withHeader`, `Request.send` | `Request.withRequestHeader`, `Request.sendRequest` |
| `Graph.insert`, `Graph.neighbors` | `Graph.insertGraphNode`, `Graph.graphNeighbors` |

## Design for qualified imports

**Problem:** APIs designed around `import Parser exposing (..)` make dependencies hard to trace in large codebases and invite naming conflicts.

**Guideline:** The API should read well and encourage namespaced usage:

```elm
import Graph
import Parser
import Request

Parser.parse source

Request.send request

Graph.neighbors node graph
```

## Evaluate call-site readability

**Problem:** Type signatures can look fine while the code users actually write is awkward.

**Guideline:** Review realistic call sites, not just signatures. Aim for code like:

```elm
request =
    Request.get "/users"
        |> Request.withHeader "Authorization" token
        |> Request.withTimeout 5000
```

Ask:

- Does qualified usage read naturally? Do pipelines?
- Is the primary value last?
- Can a new reader tell where functions come from?
- Are important domain concepts visible?
- Is there unnecessary ceremony?

## Design workflow

When designing a new package or module:

1. **Define the use case.** State the concrete user problem.
2. **Write example usage.** Realistic Elm call sites, before settling on types.
3. **Identify the minimum public concepts:** types, constructors, queries, transformations, conversions. Keep the surface as small as practical.
4. **Choose representation boundaries.** Decide which package-owned values are opaque; keep constructors private when representation is an implementation detail.
5. **Design signatures.** Primary data structure last; readable names; no module-name repetition; natural composition; no adapters needed for common operations.
6. **Test with multiple examples:** the simplest common case, a more complex realistic case, composition with `|>`, and composition with `List.map`/`foldl`/similar when relevant.
7. **Remove unnecessary abstraction.** For every public abstraction, name the specific problem it solves; delete or simplify anything without demonstrated value.
8. **Design documentation structure.** Group functions by how users learn the API; add examples for important operations.
9. **Review evolution risk.** What future implementation changes would break users? Look for exposed constructors, exposed record fields, public tuples representing domain concepts, public aliases revealing implementation structure, and functions tied unnecessarily to internal representation.

Unless the problem requires otherwise, generated APIs should: start from example usage, keep the public API minimal, prefer opaque package-owned types with private constructors, put the primary data structure last, use readable names without module-name repetition, work with qualified imports, include documentation examples, and avoid abstractions without demonstrated user benefit.

## Review checklist

**Use case**
- Is there a clearly defined concrete problem?
- Can the intended usage be demonstrated with realistic code?
- Does every major abstraction support that use case?

**Abstraction**
- Is any part of the API more generic than necessary?
- Can any public abstraction be removed?
- Does each abstraction demonstrably improve user code?

**Composition**
- Is the primary data structure usually the last argument?
- Do functions work naturally with `|>`?
- Do higher-order functions compose without `flip` or adapters?

**Encapsulation**
- Are package-owned domain types opaque where appropriate?
- Are constructors private unless users need pattern matching?
- Are internal record representations hidden?
- Can the representation evolve without forcing unnecessary major releases?

**Naming**
- Are names readable, avoiding unnecessary abbreviations?
- Do function names avoid repeating the module name?
- Does qualified usage read naturally?

**Documentation**
- Are important functions documented with examples?
- Is there a module-level example where useful?
- Are functions ordered by how users learn the API, under meaningful sections?

**Call sites**
- Does realistic user code look simple?
- Can a reader identify where functions come from?
- Are common operations concise without becoming cryptic?
- Is the API pleasant to use without `exposing (..)`?

## Reporting review findings

Don't just flag violations mechanically. For each issue:

1. Show the relevant existing API.
2. Explain how it affects user code.
3. Show a concrete improved API.
4. Show the resulting call site.
5. Explain why the proposed design is easier to use or evolve.

Prefer concrete recommendations over abstract style commentary. The `without` → `remove` example under *Put the data structure last* is the model: current signature, the awkward `foldr (flip without) people names`, the improved signature, the clean `foldr remove people names`, and why argument order improves composition.
