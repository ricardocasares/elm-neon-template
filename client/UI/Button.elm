module UI.Button exposing
    ( Button, Text, Icon, Ready, NeedsContent, NeedsLabel
    , new
    , text, icon, label
    , startIcon, endIcon
    , destructive, outline, secondary, ghost, link
    , extraSmall, small, large
    , rounded
    , toHtml, toAnchor, toAttributes
    )

{-| Displays a button, a link that looks like a button, or the button styles for another element.

A button is built with `new`, given its content, adjusted with setters, and rendered with `toHtml`:

    Button.new
        |> Button.text "Save"
        |> Button.toHtml [ onClick Save ]

    Button.new
        |> Button.text "Cancel"
        |> Button.outline
        |> Button.small
        |> Button.toHtml []

Every button needs content. `toHtml` won't accept a button until it has a `text` label, or an `icon` and the accessible `label` that goes with it:

    Button.new
        |> Button.icon (Phosphor.cube Bold |> Phosphor.toHtml [])
        |> Button.label "A cube"
        |> Button.outline
        |> Button.toHtml []

A button that navigates is rendered with [`toAnchor`](#toAnchor) instead, see [Rendering](#rendering).

`toHtml` sets `type="button"`, so the button doesn't submit forms unless you pass `type_ "submit"`.

@docs Button, Text, Icon, Ready, NeedsContent, NeedsLabel


# Constructor

@docs new


# Content

@docs text, icon, label


# Setters

Variants, sizes and shape can be applied before or after the content. `startIcon` and `endIcon` need a `text` button, so they come after it.

@docs startIcon, endIcon


## Variants

The default variant is a solid primary button. When several variants are given, the last one wins.

@docs destructive, outline, secondary, ghost, link


## Sizes

Icon-only buttons are square versions of the same sizes. When several sizes are given, the last one wins.

@docs extraSmall, small, large


## Shape

The default shape has rounded corners that scale with the size.

@docs rounded


# Rendering

@docs toHtml, toAnchor, toAttributes

A button that navigates is rendered as a link with `toAnchor`. It takes the same content and setters as `toHtml`:

    Button.new
        |> Button.text "Login"
        |> Button.secondary
        |> Button.toAnchor [ href "/login" ]

Not to be confused with the [`link`](#link) variant, which makes a `<button>` look like a text link.

For any other element, `toAttributes` gives the styles alone. It accepts a button without content:

    span
        (Button.toAttributes
            (Button.new
                |> Button.outline
            )
        )
        [ text "Not a button" ]

-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class, type_)


{-| A button being built.

`shape` is [`Text`](#Text) or [`Icon`](#Icon) once the content is set. `status` is [`Ready`](#Ready) once the button can be rendered, [`NeedsContent`](#NeedsContent) while it has no content, or [`NeedsLabel`](#NeedsLabel) while an icon button still lacks its label.

-}
type Button shape status msg
    = Button
        { variant : Variant
        , size : Size
        , radius : Radius
        , content : Content msg
        }


{-| A button with a text label, made with [`text`](#text).
-}
type Text
    = Text


{-| A square button with a single icon, made with [`icon`](#icon).
-}
type Icon
    = Icon


{-| The button can be rendered.
-}
type Ready
    = Ready


{-| A button that still needs [`text`](#text) or [`icon`](#icon) before it can be rendered.
-}
type NeedsContent
    = NeedsContent


{-| An icon button that still needs [`label`](#label) before it can be rendered.
-}
type NeedsLabel
    = NeedsLabel


type Content msg
    = Empty
    | Words
        { text : String
        , start : Maybe (Html msg)
        , end : Maybe (Html msg)
        }
    | Glyph
        { name : String
        , icon : Html msg
        }


type Variant
    = Default
    | Destructive
    | Outline
    | Secondary
    | Ghost
    | Link


type Size
    = Medium
    | ExtraSmall
    | Small
    | Large


type Radius
    = Corners
    | Pill



-- CONSTRUCTOR


{-| An empty button. Give it [`text`](#text), or an [`icon`](#icon) and a [`label`](#label), to make it renderable.
-}
new : Button shape NeedsContent msg
new =
    Button { variant = Default, size = Medium, radius = Corners, content = Empty }



-- CONTENT


{-| A text label. The button becomes renderable.
-}
text : String -> Button shape NeedsContent msg -> Button Text Ready msg
text string (Button config) =
    Button { config | content = Words { text = string, start = Nothing, end = Nothing } }


{-| A single icon, making a square button. Give it an accessible name with [`label`](#label).
-}
icon : Html msg -> Button shape NeedsContent msg -> Button Icon NeedsLabel msg
icon child (Button config) =
    Button { config | content = Glyph { name = "", icon = child } }


{-| The accessible name of an icon button, set as `aria-label`. The button becomes renderable.
-}
label : String -> Button Icon NeedsLabel msg -> Button Icon Ready msg
label name (Button config) =
    case config.content of
        Glyph glyph ->
            Button { config | content = Glyph { glyph | name = name } }

        _ ->
            Button config



-- RENDERING


{-| Renders a `<button type="button">` with the given attributes after the styles, so they can override them.
-}
toHtml : List (Attribute msg) -> Button shape Ready msg -> Html msg
toHtml attrs =
    render Html.button (type_ "button" :: attrs)


{-| Renders an `<a>` with the button styles and content. Pass `href` with the attributes.
-}
toAnchor : List (Attribute msg) -> Button shape Ready msg -> Html msg
toAnchor =
    render Html.a


render : (List (Attribute msg) -> List (Html msg) -> Html msg) -> List (Attribute msg) -> Button shape Ready msg -> Html msg
render element attrs ((Button config) as button) =
    element
        (attribute "data-slot" "button" :: toAttributes button ++ ariaLabel config.content ++ attrs)
        (children config.content)


ariaLabel : Content msg -> List (Attribute msg)
ariaLabel content =
    case content of
        Glyph { name } ->
            [ attribute "aria-label" name, attribute "title" name ]

        _ ->
            []


children : Content msg -> List (Html msg)
children content =
    case content of
        Words words ->
            List.filterMap identity
                [ Maybe.map (iconSlot "inline-start") words.start
                , Just (Html.text words.text)
                , Maybe.map (iconSlot "inline-end") words.end
                ]

        Glyph config ->
            [ config.icon ]

        Empty ->
            []


iconSlot : String -> Html msg -> Html msg
iconSlot position child =
    Html.span [ attribute "data-icon" position, class "contents" ] [ child ]


{-| The button styles alone, for elements other than `<button>` and `<a>`. Any button is accepted, including one without content.
-}
toAttributes : Button shape status msg -> List (Attribute msg)
toAttributes (Button config) =
    [ class "group/button inline-flex shrink-0 items-center justify-center border bg-clip-padding font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:ring-3 active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0"
    , class (variantClass config.variant)
    , class (sizeClass config.content config.size)
    , class (radiusClass config.size config.radius)
    ]



-- SETTERS


{-| An icon before the label. The padding is adjusted for it.
-}
startIcon : Html msg -> Button Text Ready msg -> Button Text Ready msg
startIcon child =
    mapText (\words -> { words | start = Just child })


{-| An icon after the label. The padding is adjusted for it.
-}
endIcon : Html msg -> Button Text Ready msg -> Button Text Ready msg
endIcon child =
    mapText (\words -> { words | end = Just child })


mapText :
    ({ text : String, start : Maybe (Html msg), end : Maybe (Html msg) } -> { text : String, start : Maybe (Html msg), end : Maybe (Html msg) })
    -> Button Text Ready msg
    -> Button Text Ready msg
mapText f (Button config) =
    case config.content of
        Words words ->
            Button { config | content = Words (f words) }

        _ ->
            Button config


variant : Variant -> Button shape status msg -> Button shape status msg
variant v (Button config) =
    Button { config | variant = v }


size : Size -> Button shape status msg -> Button shape status msg
size s (Button config) =
    Button { config | size = s }


{-| -}
destructive : Button shape status msg -> Button shape status msg
destructive =
    variant Destructive


{-| -}
outline : Button shape status msg -> Button shape status msg
outline =
    variant Outline


{-| -}
secondary : Button shape status msg -> Button shape status msg
secondary =
    variant Secondary


{-| -}
ghost : Button shape status msg -> Button shape status msg
ghost =
    variant Ghost


{-| Looks like a text link.
-}
link : Button shape status msg -> Button shape status msg
link =
    variant Link


{-| -}
extraSmall : Button shape status msg -> Button shape status msg
extraSmall =
    size ExtraSmall


{-| -}
small : Button shape status msg -> Button shape status msg
small =
    size Small


{-| -}
large : Button shape status msg -> Button shape status msg
large =
    size Large


{-| A pill shape, for any size. Replaces the default corner radius, so no class override is needed.
-}
rounded : Button shape status msg -> Button shape status msg
rounded (Button config) =
    Button { config | radius = Pill }



-- shadcn merges its base, variant and size classes with tailwind-merge, which drops
-- the base classes a variant or size overrides. Elm keeps every class, so classes
-- that differ by variant or size live only in `variantClass` and `sizeClass`.


variantClass : Variant -> String
variantClass v =
    case v of
        Default ->
            "border-transparent bg-primary text-primary-foreground hover:bg-primary/80 focus-visible:border-ring focus-visible:ring-ring/50"

        Destructive ->
            "border-transparent bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30 dark:focus-visible:ring-destructive/40"

        Outline ->
            "border-border bg-background hover:bg-muted hover:text-foreground focus-visible:border-ring focus-visible:ring-ring/50 aria-expanded:bg-muted aria-expanded:text-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50"

        Secondary ->
            "border-transparent bg-secondary text-secondary-foreground hover:bg-[color-mix(in_oklch,var(--secondary),var(--foreground)_5%)] focus-visible:border-ring focus-visible:ring-ring/50 aria-expanded:bg-secondary aria-expanded:text-secondary-foreground"

        Ghost ->
            "border-transparent hover:bg-muted hover:text-foreground focus-visible:border-ring focus-visible:ring-ring/50 aria-expanded:bg-muted aria-expanded:text-foreground dark:hover:bg-muted/50"

        Link ->
            "border-transparent text-primary underline-offset-4 hover:underline focus-visible:border-ring focus-visible:ring-ring/50"


sizeClass : Content msg -> Size -> String
sizeClass content size_ =
    case content of
        Glyph _ ->
            iconSizeClass size_

        _ ->
            labeledSizeClass size_


labeledSizeClass : Size -> String
labeledSizeClass size_ =
    case size_ of
        Medium ->
            "h-8 gap-1.5 px-2.5 text-sm has-data-[icon=inline-end]:pe-2 has-data-[icon=inline-start]:ps-2 [&_svg:not([class*='size-'])]:size-4"

        ExtraSmall ->
            "h-6 gap-1 px-2 text-xs has-data-[icon=inline-end]:pe-1.5 has-data-[icon=inline-start]:ps-1.5 [&_svg:not([class*='size-'])]:size-3"

        Small ->
            "h-7 gap-1 px-2.5 text-[0.8rem] has-data-[icon=inline-end]:pe-1.5 has-data-[icon=inline-start]:ps-1.5 [&_svg:not([class*='size-'])]:size-3.5"

        Large ->
            "h-9 gap-1.5 px-2.5 text-sm has-data-[icon=inline-end]:pe-2 has-data-[icon=inline-start]:ps-2 [&_svg:not([class*='size-'])]:size-4"


iconSizeClass : Size -> String
iconSizeClass size_ =
    case size_ of
        Medium ->
            "size-8 text-sm [&_svg:not([class*='size-'])]:size-4"

        ExtraSmall ->
            "size-6 text-sm [&_svg:not([class*='size-'])]:size-3"

        Small ->
            "size-7 text-sm [&_svg:not([class*='size-'])]:size-4"

        Large ->
            "size-9 text-sm [&_svg:not([class*='size-'])]:size-4"


radiusClass : Size -> Radius -> String
radiusClass size_ radius =
    case radius of
        Pill ->
            "rounded-full"

        Corners ->
            case size_ of
                Medium ->
                    "rounded-lg"

                ExtraSmall ->
                    "rounded-[min(var(--radius-md),10px)] in-data-[slot=button-group]:rounded-lg"

                Small ->
                    "rounded-[min(var(--radius-md),12px)] in-data-[slot=button-group]:rounded-lg"

                Large ->
                    "rounded-lg"
