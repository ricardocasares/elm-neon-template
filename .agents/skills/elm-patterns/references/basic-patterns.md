# Basic Elm Patterns

Data modeling and API design patterns. Adapted from [Elm Patterns](https://sporto.github.io/elm-patterns/) by Sebastian Porto.

## Type blindness

**Problem:** Several values share a primitive type and can be silently mixed up. Two `String` fields (`firstName`, `lastName`) can be swapped; two `Float` prices in different currencies can be added: `priceInDollars + priceInEuros` compiles but is nonsense.

**Pattern:** Wrap values in a single-constructor custom type so the compiler tells them apart.

```elm
type Dollar
    = Dollar Float

priceInDollars : Dollar
priceInDollars =
    Dollar 2.0
```

**When to use:** When there is real potential to confuse values. Wrapping/unwrapping adds friction, so skip it for values that never travel together.

Source: [Type blindness](https://sporto.github.io/elm-patterns/basic/type-blindness.html)

## Minimize boolean usage

**Problem:** Booleans hide intent (boolean *ambiguity*) and discard information the compiler could use (boolean *blindness*).

- Ambiguity: `bookFlight "ELM" True` — what does `True` mean at the call site?
- Blindness: `if isValid formData then submitForm formData else ...` — the `Bool` proves nothing; the compiler won't complain if the branches are swapped, and `submitForm` still receives unvalidated data.

**Pattern:** Replace boolean arguments with a custom type, and boolean returns with a type that carries evidence:

```elm
type CustomerStatus
    = Premium
    | Regular
    | Economy

bookFlight "ELM" Premium
```

```elm
case validate formData of
    Ok validFormData ->
        submitForm validFormData   -- can only be called with valid data

    Err errors ->
        showErrors errors
```

**When to use:** Any time a `Bool` argument is unclear at the call site, or a `Bool` return immediately feeds an `if`. A genuine two-state flag with obvious meaning (e.g. `disabled`) is fine.

Source: [Minimize boolean usage](https://sporto.github.io/elm-patterns/basic/minimize-boolean.html)

## Named arguments

**Problem:** Same-typed positional arguments are ambiguous: in `isBefore : Date -> Date -> Bool`, which date is the subject?

**Pattern:** Take a record instead:

```elm
isBefore : { subject : Date, comparedTo : Date } -> Bool
```

**Trade-off:** Less pipeline-friendly, but precise and hard to misuse. Use when argument order is easy to get wrong.

Source: [Named arguments](https://sporto.github.io/elm-patterns/basic/named-arguments.html)

## Wrap early, unwrap late

**Problem:** Even with wrapper types defined, functions that take primitives (`displayPriceInDollars : Float -> String`) reintroduce type blindness at every boundary.

**Pattern:** Wrap values in their unique type as early as possible (e.g. in the JSON decoder), pass the wrapped type everywhere, and unwrap at the last moment:

```elm
type Dollar
    = Dollar Float

displayPriceInDollars : Dollar -> String
displayPriceInDollars (Dollar price) =
    "USD$" ++ String.fromFloat price
```

Source: [Wrap early, unwrap late](https://sporto.github.io/elm-patterns/basic/wrap-early.html)

## Unwrap Maybe and Result early

**Problem:** Passing `Maybe`/`Result`/`RemoteData` values deep into view helpers forces every helper to unwrap them again.

```elm
-- Anti-pattern: both children receive Maybe User
userCard : Maybe User -> Html Msg
userCard maybeUser =
    div [] [ userInfo maybeUser, userActivity maybeUser ]
```

**Pattern:** Case on the wrapper once, at the top; children take the plain value:

```elm
userCard : Maybe User -> Html Msg
userCard maybeUser =
    case maybeUser of
        Nothing ->
            emptyCard

        Just user ->
            div [] [ userInfo user, userActivity user ]
```

Child views taking `User` (not `Maybe User`) are easier to write and test.

Source: [Unwrap Maybe early](https://sporto.github.io/elm-patterns/basic/unwrap-maybe-early.html)

## Make impossible states impossible

**Problem:** Independent fields allow contradictory combinations:

```elm
-- Anti-pattern: what does isLoading = False, data = Nothing mean?
type alias Model =
    { isLoading : Bool
    , data : Maybe Data
    }
```

**Pattern:** Model the states as one custom type so only valid combinations exist:

```elm
type RemoteData
    = Loading
    | Loaded Data

type alias Model =
    { data : RemoteData }
```

Extend with `NotAsked` / `Failure Error` variants as needed (see the `krisajenkins/remotedata` package). Apply whenever two fields must stay in sync — encode the sync in the type instead.

Source: [Make impossible states impossible](https://sporto.github.io/elm-patterns/basic/impossible-states.html) · [Richard Feldman's talk](https://www.youtube.com/watch?v=IcgmSRJHu_8)

## Parse, don't validate

**Problem:** A validation check like `isValidUser : UserInput -> Bool` leaves you holding the same possibly-invalid type afterward; nothing stops later code from using unvalidated data.

**Pattern:** Parse the loose input into a distinct, known-valid type:

```elm
type alias UserInput =
    { name : Maybe String
    , age : Maybe Int
    }

type alias ValidUser =
    { name : String
    , age : Int
    }

validateUser : UserInput -> Result String ValidUser
```

Downstream functions take `ValidUser` and cannot receive unchecked data. Use for form input, JSON from external sources, URL params — any boundary data.

Source: [Parse don't validate](https://sporto.github.io/elm-patterns/basic/parse-dont-validate.html)

## The builder pattern

**Problem:** A function taking a full args record (`btn : Args -> Html msg`) forces every caller to change whenever a field is added to `Args`.

**Pattern:** Expose a constructor with the minimum required info plus `with*` modifiers:

```elm
module Button exposing (Args, btn, newArgs, withHexColor, withIsEnabled)

newArgs : String -> Args
newArgs label =
    { isEnabled = True, label = label, hexColor = "#ABC" }

withIsEnabled : Bool -> Args -> Args
withIsEnabled isEnabled args =
    { args | isEnabled = isEnabled }

btn : Args -> Html msg
```

```elm
Button.newArgs "Click me"
    |> Button.withIsEnabled False
    |> Button.withHexColor "#123"
    |> Button.btn
```

Adding a field with a default no longer touches callers. Also excellent as test factories: build a baseline record, tweak per test. Pairs well with opaque types (hide `Args`).

Source: [The builder pattern](https://sporto.github.io/elm-patterns/basic/builder-pattern.html)

## Arguments list

**Problem:** Same configuration need as the builder pattern, when *all* settings are optional.

**Pattern:** Expose functions that each return a common (ideally opaque) type, and take a `List` of them — the style of `elm/html`, `elm/svg`, `elm-css`, and `elm-ui`:

```elm
scale : Float -> Float -> Float -> Attribute
rotation : Int -> Int -> Int -> Attribute

view =
    shape
        [ scale 0.5 0.5 0.5
        , position 0 -6 -13
        , rotation -90 0 0
        ]
```

**When to use:** All settings optional (an empty list must be meaningful). Prefer the builder pattern when some settings are required.

Source: [Arguments list](https://sporto.github.io/elm-patterns/basic/arguments-list.html)

## Type iterator

**Problem:** A hand-maintained `all : List Color` of every variant silently goes stale when a variant is added.

**Pattern (option 1):** The [`NoMissingTypeConstructor`](https://package.elm-lang.org/packages/Arkham/elm-review-no-missing-type-constructor/latest/) elm-review rule checks `all*` lists automatically.

**Pattern (option 2):** Build the list through a `case` so the compiler flags missing variants:

```elm
all : List Color
all =
    next [] |> List.reverse

next : List Color -> List Color
next list =
    case List.head list of
        Nothing ->
            Red :: list |> next

        Just Red ->
            Yellow :: list |> next

        Just Yellow ->
            Green :: list |> next

        Just Green ->
            list
```

Never use a `_` wildcard in `next` — it would defeat the exhaustiveness check.

Source: [Type iterator](https://sporto.github.io/elm-patterns/basic/type-iterator.html)

## Conditional rendering

Three idioms for "sometimes render this element":

```elm
-- 1. Maybes + filterMap
[ Just headerElement
, maybeBanner showBanner   -- returns Maybe (Html msg)
, Just content
]
    |> List.filterMap identity
```

```elm
-- 2. No-op element: text "" renders nothing (class "" for attributes)
maybeBanner showBanner =
    if showBanner then
        bannerElement

    else
        text ""
```

```elm
-- 3. List concatenation: return [] to render nothing
[ headerElement ] ++ maybeBanner showBanner ++ [ content ]
```

All three are idiomatic; pick per context. `text ""` is the lightest for a single element; `filterMap`/concat scale better for several conditional siblings.

Source: [Conditional rendering](https://sporto.github.io/elm-patterns/basic/conditional-rendering.html)
