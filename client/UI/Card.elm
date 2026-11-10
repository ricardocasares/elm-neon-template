module UI.Card exposing
    ( Card
    , new
    , title, description, action, image, content, footer
    , small
    , toHtml
    )

{-| Displays a card with header, content, and footer.

A card is built with `new`, filled in with setters, and rendered with `toHtml`:

    Card.new
        |> Card.title [ text "Notifications" ]
        |> Card.description [ text "You have 3 unread messages." ]
        |> Card.action
            (Button.new
                |> Button.text "Mark all read"
                |> Button.link
                |> Button.toHtml []
            )
        |> Card.content [] [ text "…" ]
        |> Card.footer []
            [ Button.new
                |> Button.text "Done"
                |> Button.toHtml [ class "w-full" ]
            ]
        |> Card.toHtml [ class "w-full max-w-sm" ]

Every part is optional. The header appears when the card has a `title`, a `description` or an `action`, and the footer is separated by a border on a muted background.

@docs Card


# Constructor

@docs new


# Setters

@docs title, description, action, image, content, footer


# Sizes

The default card has roomier spacing. Use `small` for a denser one.

@docs small


# Rendering

@docs toHtml

Spacing between and inside the parts comes from the `--card-spacing` variable, which `toHtml` accepts an override for:

    Card.new
        |> Card.title [ text "Roomier" ]
        |> Card.toHtml [ class "[--card-spacing:--spacing(6)]" ]

Content can run edge to edge with negative margins of the same variable, and `-mb-(--card-spacing)` on the content removes the gap above the footer.

-}

import Html exposing (Attribute, Html, div, img)
import Html.Attributes exposing (attribute, class)


{-| A card being built.
-}
type Card msg
    = Card
        { size : Size
        , image : Maybe (List (Attribute msg))
        , title : List (Html msg)
        , description : List (Html msg)
        , action : Maybe (Html msg)
        , content : Maybe ( List (Attribute msg), List (Html msg) )
        , footer : Maybe ( List (Attribute msg), List (Html msg) )
        }


type Size
    = Default
    | Small



-- CONSTRUCTOR


{-| An empty card.
-}
new : Card msg
new =
    Card
        { size = Default
        , image = Nothing
        , title = []
        , description = []
        , action = Nothing
        , content = Nothing
        , footer = Nothing
        }



-- SETTERS


{-| The heading of the card.
-}
title : List (Html msg) -> Card msg -> Card msg
title children (Card config) =
    Card { config | title = children }


{-| Supporting text below the title.
-}
description : List (Html msg) -> Card msg -> Card msg
description children (Card config) =
    Card { config | description = children }


{-| A control, such as a button or a badge, placed in the top-right corner of the header.
-}
action : Html msg -> Card msg -> Card msg
action child (Card config) =
    Card { config | action = Just child }


{-| An image above the header, running edge to edge with the card's rounded top corners. Give it `src` and `alt`; it keeps a 16:9 ratio and covers its box.
-}
image : List (Attribute msg) -> Card msg -> Card msg
image attrs (Card config) =
    Card { config | image = Just attrs }


{-| The body of the card, with attributes after the styles so they can override them.
-}
content : List (Attribute msg) -> List (Html msg) -> Card msg -> Card msg
content attrs children (Card config) =
    Card { config | content = Just ( attrs, children ) }


{-| The bottom of the card, with its items in a row. Pass `flex-col` to stack them, or `justify-end` to push them right.
-}
footer : List (Attribute msg) -> List (Html msg) -> Card msg -> Card msg
footer attrs children (Card config) =
    Card { config | footer = Just ( attrs, children ) }


{-| -}
small : Card msg -> Card msg
small (Card config) =
    Card { config | size = Small }



-- RENDERING


{-| Renders the card with the given attributes after the styles, so they can override them.
-}
toHtml : List (Attribute msg) -> Card msg -> Html msg
toHtml attrs (Card config) =
    let
        hasHeader =
            not (List.isEmpty config.title && List.isEmpty config.description && config.action == Nothing)
    in
    div
        ([ attribute "data-slot" "card"
         , attribute "data-size" (sizeName config.size)
         , class "group/card flex flex-col gap-(--card-spacing) overflow-hidden rounded-xl bg-card py-(--card-spacing) text-sm text-card-foreground ring-1 ring-foreground/10 [--card-spacing:--spacing(4)] has-data-[slot=card-footer]:pb-0 has-[>img:first-child]:pt-0 data-[size=sm]:[--card-spacing:--spacing(3)] *:[img:first-child]:rounded-t-xl *:[img:last-child]:rounded-b-xl"
         ]
            ++ attrs
        )
        (List.filterMap identity
            [ Maybe.map (\imageAttrs -> img (class "aspect-video w-full object-cover" :: imageAttrs) []) config.image
            , if hasHeader then
                Just
                    (div
                        [ attribute "data-slot" "card-header"
                        , class "group/card-header @container/card-header grid auto-rows-min items-start gap-1 rounded-t-xl px-(--card-spacing) has-data-[slot=card-action]:grid-cols-[1fr_auto] has-data-[slot=card-description]:grid-rows-[auto_auto] [.border-b]:pb-(--card-spacing)"
                        ]
                        (List.filterMap identity
                            [ if List.isEmpty config.title then
                                Nothing

                              else
                                Just (slot "card-title" "text-base leading-snug font-medium group-data-[size=sm]/card:text-sm" config.title)
                            , if List.isEmpty config.description then
                                Nothing

                              else
                                Just (slot "card-description" "text-sm text-muted-foreground" config.description)
                            , Maybe.map (\child -> slot "card-action" "col-start-2 row-span-2 row-start-1 self-start justify-self-end" [ child ]) config.action
                            ]
                        )
                    )

              else
                Nothing
            , Maybe.map (part "card-content" "px-(--card-spacing)") config.content
            , Maybe.map (part "card-footer" "flex items-center rounded-b-xl border-t bg-muted/50 p-(--card-spacing)") config.footer
            ]
        )


slot : String -> String -> List (Html msg) -> Html msg
slot name classes children =
    div [ attribute "data-slot" name, class classes ] children


part : String -> String -> ( List (Attribute msg), List (Html msg) ) -> Html msg
part name classes ( attrs, children ) =
    div (attribute "data-slot" name :: class classes :: attrs) children


sizeName : Size -> String
sizeName size =
    case size of
        Default ->
            "default"

        Small ->
            "sm"
