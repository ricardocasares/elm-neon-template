module UI.Badge exposing
    ( Badge, Ready, NeedsText
    , new
    , text
    , startIcon, endIcon
    , secondary, destructive, outline, ghost, link
    , toHtml, toAnchor, toAttributes
    )

{-| Displays a badge or a component that looks like a badge.

A badge is built with `new`, given its text, adjusted with setters, and rendered with `toHtml`:

    Badge.new
        |> Badge.text "New"
        |> Badge.toHtml []

    Badge.new
        |> Badge.text "Draft"
        |> Badge.outline
        |> Badge.toHtml []

Every badge needs text. `toHtml` won't accept a badge until it has it:

    Badge.new
        |> Badge.secondary
        |> Badge.toHtml []
        -- compile error: the badge is still `NeedsText`

Icons go before or after the text, and the padding is adjusted for them:

    Badge.new
        |> Badge.text "Verified"
        |> Badge.secondary
        |> Badge.startIcon (Phosphor.sealCheck Regular |> Phosphor.toHtml [])
        |> Badge.toHtml []

@docs Badge, Ready, NeedsText


# Constructor

@docs new


# Content

@docs text


# Setters

Variants can be applied before or after the text. `startIcon` and `endIcon` need the text, so they come after it.

@docs startIcon, endIcon


## Variants

The default variant is a solid primary badge. When several variants are given, the last one wins.

@docs secondary, destructive, outline, ghost, link


# Rendering

@docs toHtml, toAnchor, toAttributes

A badge that navigates is rendered as a link with `toAnchor`. Links also get a hover state:

    Badge.new
        |> Badge.text "12 unread"
        |> Badge.secondary
        |> Badge.toAnchor [ href "/inbox" ]

For any other element, `toAttributes` gives the styles alone. It accepts a badge without text:

    span
        (Badge.toAttributes
            (Badge.new
                |> Badge.outline
            )
        )
        [ text "Not a badge" ]

-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class)


{-| A badge being built.

`status` is [`Ready`](#Ready) once the badge can be rendered, or [`NeedsText`](#NeedsText) while it still lacks its text.

-}
type Badge status msg
    = Badge
        { variant : Variant
        , text : String
        , start : Maybe (Html msg)
        , end : Maybe (Html msg)
        }


{-| The badge can be rendered.
-}
type Ready
    = Ready


{-| A badge that still needs [`text`](#text) before it can be rendered.
-}
type NeedsText
    = NeedsText


type Variant
    = Default
    | Secondary
    | Destructive
    | Outline
    | Ghost
    | Link



-- CONSTRUCTOR


{-| An empty badge. Give it [`text`](#text) to make it renderable.
-}
new : Badge NeedsText msg
new =
    Badge
        { variant = Default
        , text = ""
        , start = Nothing
        , end = Nothing
        }



-- CONTENT


{-| The text of the badge. Required.
-}
text : String -> Badge status msg -> Badge Ready msg
text string (Badge config) =
    Badge { config | text = string }



-- SETTERS


{-| An icon before the text. The padding is adjusted for it.
-}
startIcon : Html msg -> Badge Ready msg -> Badge Ready msg
startIcon child (Badge config) =
    Badge { config | start = Just child }


{-| An icon after the text. The padding is adjusted for it.
-}
endIcon : Html msg -> Badge Ready msg -> Badge Ready msg
endIcon child (Badge config) =
    Badge { config | end = Just child }


{-| -}
secondary : Badge status msg -> Badge status msg
secondary =
    variant Secondary


{-| -}
destructive : Badge status msg -> Badge status msg
destructive =
    variant Destructive


{-| -}
outline : Badge status msg -> Badge status msg
outline =
    variant Outline


{-| -}
ghost : Badge status msg -> Badge status msg
ghost =
    variant Ghost


{-| -}
link : Badge status msg -> Badge status msg
link =
    variant Link


variant : Variant -> Badge status msg -> Badge status msg
variant value (Badge config) =
    Badge { config | variant = value }



-- RENDERING


{-| Renders a `<span>` with the given attributes after the styles, so they can override them.
-}
toHtml : List (Attribute msg) -> Badge Ready msg -> Html msg
toHtml =
    render Html.span


{-| Renders an `<a>` with the badge styles and content. Pass `href` with the attributes.
-}
toAnchor : List (Attribute msg) -> Badge Ready msg -> Html msg
toAnchor =
    render Html.a


render : (List (Attribute msg) -> List (Html msg) -> Html msg) -> List (Attribute msg) -> Badge Ready msg -> Html msg
render element attrs ((Badge config) as badge) =
    element
        (toAttributes badge ++ attrs)
        (List.filterMap identity
            [ Maybe.map (iconSlot "inline-start") config.start
            , Just (Html.text config.text)
            , Maybe.map (iconSlot "inline-end") config.end
            ]
        )


iconSlot : String -> Html msg -> Html msg
iconSlot position child =
    Html.span [ attribute "data-icon" position, class "contents" ] [ child ]


{-| The badge styles alone, for elements other than `<span>` and `<a>`. Any badge is accepted, including one without text.
-}
toAttributes : Badge status msg -> List (Attribute msg)
toAttributes (Badge config) =
    [ attribute "data-slot" "badge"
    , attribute "data-variant" (variantName config.variant)
    , class "group/badge inline-flex h-5 w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-4xl border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap transition-all focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 has-data-[icon=inline-end]:pe-1.5 has-data-[icon=inline-start]:ps-1.5 aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:size-3! [&_[data-slot=spinner]]:size-3"
    , class (variantClass config.variant)
    ]


variantName : Variant -> String
variantName value =
    case value of
        Default ->
            "default"

        Secondary ->
            "secondary"

        Destructive ->
            "destructive"

        Outline ->
            "outline"

        Ghost ->
            "ghost"

        Link ->
            "link"


variantClass : Variant -> String
variantClass value =
    case value of
        Default ->
            "bg-primary text-primary-foreground [a&]:hover:bg-primary/80"

        Secondary ->
            "bg-secondary text-secondary-foreground [a&]:hover:bg-secondary/80"

        Destructive ->
            "bg-destructive/10 text-destructive focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:focus-visible:ring-destructive/40 [a&]:hover:bg-destructive/20"

        Outline ->
            "border-border text-foreground [a&]:hover:bg-muted [a&]:hover:text-muted-foreground"

        Ghost ->
            "hover:bg-muted hover:text-muted-foreground dark:hover:bg-muted/50"

        Link ->
            "text-primary underline-offset-4 hover:underline"
