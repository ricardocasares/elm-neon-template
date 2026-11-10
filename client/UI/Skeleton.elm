module UI.Skeleton exposing (view)

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class)


view : List (Attribute msg) -> Html msg
view attrs =
    Html.div (attribute "data-slot" "skeleton" :: class "animate-pulse rounded-md bg-muted" :: attrs) []
