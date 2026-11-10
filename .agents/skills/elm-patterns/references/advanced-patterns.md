# Advanced Elm Patterns

Type-system techniques: opaque types, phantom types, railway-style chaining, combinators. Adapted from [Elm Patterns](https://sporto.github.io/elm-patterns/) by Sebastian Porto.

## The railway pattern

**Problem:** Chain operations where each step can fail (parse → validate → transform).

**Pattern:** Two tracks — a happy path and an error track. Once a step fails, the rest are skipped and the error propagates. In Elm this is `Result.andThen` / `Maybe.andThen`:

```elm
parseData : String -> Result String ParsedData
validateData : ParsedData -> Result String ValidData
transformData : ValidData -> Result String TransformedData

process : String -> Result String TransformedData
process data =
    parseData data
        |> Result.andThen validateData
        |> Result.andThen transformData
```

**Variant — early exit:** the second track can mean "stop successfully" instead of "error". Define a custom type and mirror `andThen`:

```elm
type Process
    = Continue Recommendation
    | Exit Recommendation

andThen : (Recommendation -> Process) -> Process -> Process
andThen callback process =
    case process of
        Continue recommendation ->
            callback recommendation

        Exit recommendation ->
            Exit recommendation

findRecommendations user =
    Continue emptyRecommendation
        |> andThen (findMusic user)
        |> andThen (findBooks user)
```

Source: [Railway](https://sporto.github.io/elm-patterns/advanced/railway.html) · [Railway oriented programming](https://fsharpforfunandprofit.com/rop/)

## Pipeline builder

**Problem:** Build a record from a series of fallible steps (decoding, validation) without nested cases.

**Pattern:** Exploit that a record alias is a curried constructor function (`User : String -> Int -> User`). Put the constructor in a `Result` and apply one argument per piped step:

```elm
type alias User =
    { name : String
    , age : Int
    }

validateUser : User -> Result String User
validateUser user =
    Ok User
        |> validateName user.name
        |> validateAge user.age

validateName : String -> Result String (String -> a) -> Result String a
validateName name =
    Result.andThen
        (\constructor ->
            if String.isEmpty name then
                Err "Invalid name"

            else
                Ok (constructor name)
        )
```

This is how `NoRedInk/elm-json-decode-pipeline` and validation packages (`elm-verify`, `elm-validator-pipeline`) work.

**Caveat:** The pipeline applies arguments *positionally*. With several same-typed fields (`name`, `email` both `String`), swapping two steps still compiles but fills the wrong fields. Keep step order aligned with the record definition, or use distinct wrapper types.

Source: [Pipeline builder](https://sporto.github.io/elm-patterns/advanced/pipeline-builder.html)

## Opaque types

**Problem:** Exposing a type alias (`type alias Config = { size : Int, ... }`) couples every consumer to the internal structure; any change breaks callers (a major version bump for packages).

**Pattern:** Expose the type but not its constructor, plus functions to create and update values:

```elm
module Lib exposing (Config, newConfig, withSize)

type Config
    = Config { size : Int, style : Style }

newConfig : Config
newConfig =
    Config { size = 1, style = Big }

withSize : Int -> Config -> Config
```

External modules can obtain and transform a `Config` but never construct or inspect one directly, so the internals can change freely. Useful for hiding implementation (especially in packages) and enforcing invariants (next pattern).

Source: [Opaque types](https://sporto.github.io/elm-patterns/advanced/opaque-types.html)

## Opaque types for enforcing invariants

**Problem:** Data must always satisfy a rule (e.g. a list that is always sorted), but any module that can construct it can break the rule.

**Pattern:** Make the type opaque so only its home module can create or modify values, and make every exposed function preserve the invariant:

```elm
module SortedList exposing (SortedList, add, new)

type SortedList comparable
    = SortedList (List comparable)

new : SortedList comparable
new =
    SortedList []

add : comparable -> SortedList comparable -> SortedList comparable
```

Since outside code can't touch the wrapped list, a `SortedList` is sorted by construction.

Source: [Opaque types for enforcing invariants](https://sporto.github.io/elm-patterns/advanced/opaque-types-invariants.html)

## Combinators

**Pattern:** Design functions that combine values of a type into another value of the *same* type, so small parts compose into arbitrarily large structures:

```elm
and : Filter -> Filter -> Filter   -- (a AND (b OR c)) keeps composing
```

Familiar examples: `Html`, `Cmd.batch`, parsers, JSON decoders/encoders, filters, validations. Anything tree-shaped is a candidate.

**Why:** Each small part is testable in isolation; complex systems are assembled from tiny pieces; callers cherry-pick and recombine what they need.

Source: [Combinators](https://sporto.github.io/elm-patterns/advanced/combinators.html)

## Phantom types

**Pattern:** A type variable that appears on the type but in no constructor:

```elm
type Users a
    = Users (List User)
```

The unused variable lets functions restrict inputs and outputs without changing the runtime value:

```elm
type Active
    = Active

activeUsers : List User -> Users Active
activeUsers users =
    users
        |> List.filter isActive
        |> Users

usersView : Users Active -> Html msg
```

Passing unfiltered users to `usersView` fails to compile — the type system proves the filtering happened. Useful for validation evidence, invariants in functions/views, state machines, and processes.

Source: [Phantom types](https://sporto.github.io/elm-patterns/advanced/phantom-types.html)

## Process flow using phantom types

**Problem:** A multi-step process (a finite state machine) must run its steps in a valid order with none skipped. Modeling each intermediate state as its own record type (`InvalidOrder`, `OrderWithTotal`, `OrderWithQuantity`, ...) multiplies types out of hand.

**Pattern:** One wrapper with a phantom `step` variable, plus empty marker types for the states:

```elm
type Step step
    = Step Order

type Start
    = Start

type OrderWithTotal
    = OrderWithTotal

type OrderWithQuantity
    = OrderWithQuantity

type Done
    = Done
```

Transition functions encode the state machine's edges:

```elm
start : Order -> Step Start
setTotal : Int -> Step Start -> Step OrderWithTotal
adjustQuantityFromTotal : Step OrderWithTotal -> Step Done
setQuantity : Int -> Step Start -> Step OrderWithQuantity
adjustTotalFromQuantity : Step OrderWithQuantity -> Step Done
done : Step Done -> Order
```

Valid flows are then just pipelines, and invalid orderings or skipped steps do not compile:

```elm
flowPrioritizingTotal total order =
    start order
        |> setTotal total
        |> adjustQuantityFromTotal
        |> done
```

Working example: <https://ellie-app.com/smDDnCh5C8Xa1>

Source: [Process flow using phantom types](https://sporto.github.io/elm-patterns/advanced/flow-phantom-types.html)
