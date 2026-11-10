module UI.Spinner exposing (view)

{-| An indicator that shows a loading state. It is plain CSS, a ring with one transparent edge that spins.

    Spinner.view []

Size it with a `size-*` class and recolor it with a `text-*` class:

    Spinner.view [ class "size-8 text-muted-foreground" ]

@docs view

-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class)


{-| -}
view : List (Attribute msg) -> Html msg
view attrs =
    Html.span
        ([ attribute "data-slot" "spinner"
         , attribute "role" "status"
         , attribute "aria-label" "Loading"
         , class "inline-block size-4 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent"
         ]
            ++ attrs
        )
        []
