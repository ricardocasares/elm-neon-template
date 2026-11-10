# Elm Architecture Patterns

Structuring TEA applications: reusable views, nesting, parent–child communication, testable effects. Adapted from [Elm Patterns](https://sporto.github.io/elm-patterns/) by Sebastian Porto.

## Reusable views

**Pattern:** The simplest reusable "component" is a plain view function that takes message constructors from the caller — no model, no update:

```elm
type alias Args msg =
    { currentDate : Date
    , isOpen : Bool
    , onOpen : msg
    , onClose : msg
    , onSelectDate : Date -> msg
    }

calendar : Args msg -> Html msg
```

The caller owns all state (`isOpen`) and supplies its own messages. Limitations: the caller must track state, and the view cannot produce commands. Views with many optional settings are ideal candidates for the builder pattern:

```elm
Button.newArgs "Clear selection" Clear
    |> Button.withIcon IconClear
    |> Button.withSize Button.Wide
    |> Button.view
```

**Prefer this over nested TEA whenever the view doesn't truly need its own update loop.**

Source: [Reusable views](https://sporto.github.io/elm-patterns/architecture/reusable-views.html)

## Nested TEA

**Problem:** A large app's `Model`/`Msg`/`update` become unwieldy; pages want their own state.

**Pattern:** Give a child module its own `Model`, `Msg`, `update`, and `view`; the parent stores the child model, wraps child messages in a variant, and delegates:

```elm
type alias Model =
    { count : Int
    , subModel : Sub.Model
    }

type Msg
    = Increment
    | SubMsg Sub.Msg

update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        SubMsg subMsg ->
            { model | subModel = Sub.update subMsg model.subModel }

view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Increment ] [ text "+1" ]
        , Sub.view model.subModel |> Html.map SubMsg
        ]
```

**Costs:** boilerplate, and child→parent communication is awkward (see Child outcome, Translator, Global actions). Use sparingly — typically at page level in an SPA, not for widgets.

Source: [Nested TEA](https://sporto.github.io/elm-patterns/architecture/nested-tea.html)

## Child outcome

**Problem:** In nested TEA, a child needs to notify its parent after an action (e.g. "a date was picked").

**Pattern:** The child's `update` returns a third value describing what happened; the parent pattern-matches on it:

```elm
module Child exposing (Msg, Outcome(..), update)

type Outcome
    = OutcomeNone
    | OutcomeDateUpdated Date

update : Msg -> Model -> ( Model, Cmd Msg, Outcome )
```

```elm
-- in Parent.update
ChildMsg childMsg ->
    let
        ( nextChildModel, childCmd, childOutcome ) =
            Child.update childMsg model.childModel
    in
    -- act on childOutcome, store nextChildModel, map childCmd
```

Simple and explicit; the parent decides what each outcome means.

Source: [Child outcome](https://sporto.github.io/elm-patterns/architecture/child-outcome.html)

## Translator

**Problem:** With `Html.map ChildMsg`, every message a child view produces routes back to the child — the child can't emit a message destined for its parent.

**Pattern:** Make child views generic over `msg` and have the parent pass constructors in: `toSelf` for the child's own messages, plus parent messages for the rest:

```elm
module Child exposing (Args, Msg, view)

type alias Args msg =
    { toSelf : Msg -> msg
    , onSave : msg
    }

view : Model -> Args msg -> Html msg
view model args =
    div []
        [ button [ onClick (args.toSelf Clicked) ] [ text "Send to self" ]
        , button [ onClick args.onSave ] [ text "Send to parent" ]
        ]
```

```elm
module Parent exposing (..)

type Msg
    = OnSave
    | ChildMsg Child.Msg

view model =
    Child.view model.childModel
        { toSelf = ChildMsg
        , onSave = OnSave
        }
```

`toSelf` replaces `Html.map`; parent-bound messages skip the child's update entirely.

Source: [Translator](https://sporto.github.io/elm-patterns/architecture/translator.html)

## Global actions

**Problem:** Deeply nested modules need to trigger app-level behavior — show a notification, sign out — without threading it through every layer by hand.

**Pattern:** A shared `Actions` module; every nested `update` returns a list of actions, and only the root processes them:

```elm
module Actions exposing (Action(..), batch)

type Action
    = OpenSuccessNotification String
    | SignOut
```

```elm
update : Msg -> Model -> ( Model, Cmd Msg, List Action )
```

Any module in the chain appends actions; parents pass them upward; the root `update` folds over the list and executes them.

Tips: mimic `Cmd.batch` with an `Actions.batch`; if an action must send a message *back* to its origin (e.g. a selection dialog), parameterize it (`Action msg`) and provide `Actions.map` analogous to `Html.map`.

Source: [Global actions](https://sporto.github.io/elm-patterns/architecture/global-actions.html)

## The effects pattern

**Problem:** `update : Msg -> Model -> ( Model, Cmd Msg )` is hard to test — `Cmd` is opaque, so tests can neither inspect nor simulate what the update decided to do.

**Pattern:** Return a custom `Effect` type from `update` and convert to real commands at the last moment, in one place:

```elm
type Effect
    = SaveUser User
    | LogoutUser
    | LoadData

update : Msg -> Model -> ( Model, List Effect )

runEffects : List Effect -> Cmd Msg   -- only in the root module
```

Tests assert on `Effect` values directly, and tools like [elm-program-test](https://elm-program-test.netlify.app/cmds.html) can simulate them.

Source: [The effects pattern](https://sporto.github.io/elm-patterns/architecture/effects.html) · [The effect pattern blog post](http://reasonableapproximation.net/2019/10/20/the-effect-pattern.html)

## Update return pipeline

**Problem:** One `update` branch must do several things (change state, update the URL, conditionally load data, track analytics), and doing them all inline in one `let` grows complex and bug-prone.

**Pattern:** Split each concern into a `Model -> ( Model, Cmd Msg )` function and chain them with an `andThen` that batches commands:

```elm
case msg of
    SeeReport report ->
        ( model, Cmd.none )
            |> andThen (setStageToReportVisible report)
            |> andThen loadMoreDataIfNeeded
            |> andThen addKeyInUrl
            |> andThen trackSeeReportEvent

andThen : (model -> ( model, Cmd msg )) -> ( model, Cmd msg ) -> ( model, Cmd msg )
andThen fn ( model, cmd ) =
    let
        ( nextModel, nextCmd ) =
            fn model
    in
    ( nextModel, Cmd.batch [ cmd, nextCmd ] )
```

Each step does one thing:

```elm
loadMoreDataIfNeeded : Model -> ( Model, Cmd Msg )
loadMoreDataIfNeeded model =
    if needsToLoadMoreData model then
        ( { model | loading = Loading }, loadMoreDataCmd )

    else
        ( model, Cmd.none )
```

The [elm-return](https://package.elm-lang.org/packages/Fresheyeball/elm-return/latest/) package implements helpers for this.

Source: [Update return pipeline](https://sporto.github.io/elm-patterns/architecture/update-return-pipeline.html)
