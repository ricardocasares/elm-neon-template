module UI.Tabs exposing
    ( Tabs, Ready, NeedsId, NeedsHandler
    , new
    , id, onSelect
    , Tab, tab, disabled
    , tabs
    , value
    , line, vertical
    , toHtml
    )

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute, class, tabindex, type_)
import Html.Events exposing (onClick)


type Tabs a id handler msg
    = Tabs
        { id : String
        , onSelect : Maybe (a -> msg)
        , value : Maybe a
        , variant : Variant
        , orientation : Orientation
        , tabs : List (Tab a msg)
        }


type Ready
    = Ready


type NeedsId
    = NeedsId


type NeedsHandler
    = NeedsHandler


type Tab a msg
    = Tab
        { value : a
        , label : List (Html msg)
        , content : List (Html msg)
        , disabled : Bool
        }


type Variant
    = Default
    | Line


type Orientation
    = Horizontal
    | Vertical



-- CONSTRUCTOR


new : Tabs a NeedsId NeedsHandler msg
new =
    Tabs
        { id = ""
        , onSelect = Nothing
        , value = Nothing
        , variant = Default
        , orientation = Horizontal
        , tabs = []
        }



-- REQUIRED


id : String -> Tabs a NeedsId handler msg -> Tabs a Ready handler msg
id string (Tabs config) =
    Tabs { config | id = string }


onSelect : (a -> msg) -> Tabs a id NeedsHandler msg -> Tabs a id Ready msg
onSelect toMsg (Tabs config) =
    Tabs { config | onSelect = Just toMsg }



-- TABS


tab : a -> List (Html msg) -> List (Html msg) -> Tab a msg
tab v label content =
    Tab { value = v, label = label, content = content, disabled = False }


disabled : Tab a msg -> Tab a msg
disabled (Tab config) =
    Tab { config | disabled = True }


tabs : List (Tab a msg) -> Tabs a id handler msg -> Tabs a id handler msg
tabs list (Tabs config) =
    Tabs { config | tabs = list }



-- VALUE


value : a -> Tabs a id handler msg -> Tabs a id handler msg
value v (Tabs config) =
    Tabs { config | value = Just v }



-- SETTERS


line : Tabs a id handler msg -> Tabs a id handler msg
line (Tabs config) =
    Tabs { config | variant = Line }


vertical : Tabs a id handler msg -> Tabs a id handler msg
vertical (Tabs config) =
    Tabs { config | orientation = Vertical }



-- RENDERING


toHtml : List (Attribute msg) -> Tabs a Ready Ready msg -> Html msg
toHtml attrs (Tabs config) =
    let
        selected =
            case config.value of
                Just v ->
                    Just v

                Nothing ->
                    config.tabs
                        |> List.filter (\(Tab t) -> not t.disabled)
                        |> List.head
                        |> Maybe.map (\(Tab t) -> t.value)

        indexed =
            List.indexedMap Tuple.pair config.tabs

        orientation =
            case config.orientation of
                Horizontal ->
                    "horizontal"

                Vertical ->
                    "vertical"
    in
    Html.div
        ([ Html.Attributes.id config.id
         , attribute "data-slot" "tabs"
         , attribute "data-orientation" orientation
         , attribute ("data-" ++ orientation) ""
         , class "group/tabs flex gap-2 data-horizontal:flex-col"
         ]
            ++ attrs
        )
        (Html.div
            [ attribute "role" "tablist"
            , attribute "aria-orientation" orientation
            , attribute "data-slot" "tabs-list"
            , attribute "data-variant" (variantName config.variant)

            , attribute "focusgroup"
                (case config.orientation of
                    Horizontal ->
                        "tablist inline wrap"

                    Vertical ->
                        "tablist block wrap"
                )
            , class "group/tabs-list inline-flex w-fit items-center justify-center p-[3px] text-muted-foreground group-data-horizontal/tabs:h-8 group-data-vertical/tabs:h-fit group-data-vertical/tabs:flex-col"
            , class (variantClass config.variant)
            ]
            (List.map (viewTab config.id config.onSelect selected) indexed)
            :: List.filterMap (viewPanel config.id selected) indexed
        )


viewTab : String -> Maybe (a -> msg) -> Maybe a -> ( Int, Tab a msg ) -> Html msg
viewTab rootId handler selected ( index, Tab config ) =
    let
        isSelected =
            Just config.value == selected
    in
    Html.button
        ([ type_ "button"
         , Html.Attributes.id (tabId rootId index)
         , attribute "role" "tab"
         , attribute "aria-selected" (boolean isSelected)
         , attribute "data-slot" "tabs-trigger"
         , Html.Attributes.disabled config.disabled
         , tabindex
            (if isSelected then
                0

             else
                -1
            )
         , class "relative inline-flex h-[calc(100%-1px)] flex-1 items-center justify-center gap-1.5 rounded-md border border-transparent px-1.5 py-0.5 text-sm font-medium whitespace-nowrap text-foreground/60 transition-all group-data-vertical/tabs:w-full group-data-vertical/tabs:justify-start hover:text-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-1 focus-visible:outline-ring disabled:pointer-events-none disabled:opacity-50 aria-disabled:pointer-events-none aria-disabled:opacity-50 dark:text-muted-foreground dark:hover:text-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 has-data-[icon=inline-end]:pr-1 has-data-[icon=inline-start]:pl-1"
         , class "group-data-[variant=line]/tabs-list:bg-transparent group-data-[variant=line]/tabs-list:data-active:bg-transparent dark:group-data-[variant=line]/tabs-list:data-active:border-transparent dark:group-data-[variant=line]/tabs-list:data-active:bg-transparent"
         , class "data-active:bg-background data-active:text-foreground dark:data-active:border-input dark:data-active:bg-input/30 dark:data-active:text-foreground group-data-[variant=default]/tabs-list:data-active:shadow-sm group-data-[variant=line]/tabs-list:data-active:shadow-none"
         , class "after:absolute after:bg-foreground after:opacity-0 after:transition-opacity group-data-horizontal/tabs:after:inset-x-0 group-data-horizontal/tabs:after:bottom-[-5px] group-data-horizontal/tabs:after:h-0.5 group-data-vertical/tabs:after:inset-y-0 group-data-vertical/tabs:after:-right-1 group-data-vertical/tabs:after:w-0.5 group-data-[variant=line]/tabs-list:data-active:after:opacity-100"
         ]
            ++ (if isSelected then
                    [ attribute "data-active" "" ]

                else
                    []
               )
            ++ (if List.isEmpty config.content then
                    []

                else
                    [ attribute "aria-controls" (panelId rootId index) ]
               )
            ++ (case handler of
                    Just toMsg ->
                        [ onClick (toMsg config.value) ]

                    Nothing ->
                        []
               )
        )
        config.label


viewPanel : String -> Maybe a -> ( Int, Tab a msg ) -> Maybe (Html msg)
viewPanel rootId selected ( index, Tab config ) =
    if Just config.value == selected && not (List.isEmpty config.content) then
        Just
            (Html.div
                [ Html.Attributes.id (panelId rootId index)
                , attribute "role" "tabpanel"
                , attribute "aria-labelledby" (tabId rootId index)
                , attribute "data-slot" "tabs-content"
                , tabindex 0
                , class "flex-1 text-sm outline-none"
                ]
                config.content
            )

    else
        Nothing


tabId : String -> Int -> String
tabId rootId index =
    rootId ++ "-tab-" ++ String.fromInt index


panelId : String -> Int -> String
panelId rootId index =
    rootId ++ "-panel-" ++ String.fromInt index


variantClass : Variant -> String
variantClass v =
    case v of
        Default ->
            "rounded-lg bg-muted"

        Line ->
            "gap-1 rounded-none bg-transparent"


variantName : Variant -> String
variantName v =
    case v of
        Default ->
            "default"

        Line ->
            "line"


boolean : Bool -> String
boolean b =
    if b then
        "true"

    else
        "false"
