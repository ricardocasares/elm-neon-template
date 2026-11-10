module UI.Input exposing (view)

{-| Displays a form input field.

    Input.view [ type_ "email", placeholder "Email", value model.email, onInput EmailChanged ]

Set `aria-invalid` to show the error state:

    Input.view [ attribute "aria-invalid" "true" ]

@docs view

-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class)


{-| Renders an `<input>`.
-}
view : List (Attribute msg) -> Html msg
view attrs =
    Html.input
        ([ attribute "data-slot" "input"
         , class "h-8 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1 text-base transition-colors outline-none file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 md:text-sm dark:bg-input/30 dark:disabled:bg-input/80"
         , class "focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
         , class "aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40"
         ]
            ++ attrs
        )
        []
