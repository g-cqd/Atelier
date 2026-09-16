(comment) @comment

(tag_name) @tag
(nesting_selector) @tag
(universal_selector) @tag

"~" @operator
">" @operator
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"=" @operator
"^=" @operator
"|=" @operator
"~=" @operator
"$=" @operator
"*=" @operator

"and" @operator
"or" @operator
"not" @operator
"only" @operator

(attribute_selector (plain_value) @string)

((property_name) @variable
 (#match? @variable "^--"))
((plain_value) @variable
 (#match? @variable "^--"))

(class_name) @property
(id_name) @property
(namespace_name) @property
(property_name) @property
(feature_name) @property

(pseudo_element_selector (tag_name) @attribute)
(pseudo_class_selector (class_name) @attribute)
(attribute_name) @attribute

(function_name) @function

"@media" @keyword
"@import" @keyword
"@charset" @keyword
"@namespace" @keyword
"@supports" @keyword
"@keyframes" @keyword
(at_keyword) @keyword
(to) @keyword
(from) @keyword
(important) @keyword

(string_value) @string
(color_value) @string.special

(integer_value) @number
(float_value) @number
(unit) @type

[
  "#"
  ","
  "."
  ":"
  "::"
  ";"
] @punctuation.delimiter

[
  "{"
  ")"
  "("
  "}"
] @punctuation.bracket

; URL call expression
(call_expression
  function: (function_name) @function
  (#eq? @function "url"))
(call_expression (arguments (plain_value) @string))

; Vendor-prefixed properties
((property_name) @property
 (#match? @property "^-(webkit|moz|ms|o)-"))

; Common keyword values
((plain_value) @constant
 (#any-of? @constant "auto" "inherit" "initial" "unset" "revert" "none" "block" "inline" "flex" "grid" "absolute" "relative" "fixed" "sticky" "hidden" "visible" "solid" "dashed" "dotted" "bold" "italic" "normal" "center" "left" "right" "top" "bottom"))

; Selector combinators
(child_selector ">" @operator)
(sibling_selector "~" @operator)
(adjacent_sibling_selector "+" @operator)

; Modern @-rules
"@font-face" @keyword
"@page" @keyword
"@layer" @keyword
"@property" @keyword
"@container" @keyword
"@scope" @keyword

; Named pseudo-classes
((pseudo_class_selector (class_name) @attribute)
 (#any-of? @attribute "hover" "focus" "active" "visited" "first-child" "last-child" "nth-child" "first-of-type" "last-of-type" "not" "is" "where" "has"))

; Media feature names
(feature_query (feature_name) @property)

; Math and color built-in functions
((function_name) @function.builtin
 (#any-of? @function.builtin "calc" "min" "max" "clamp" "var" "env" "rgb" "rgba" "hsl" "hsla" "linear-gradient" "radial-gradient"))

; Commas in selector lists
(selectors "," @punctuation.delimiter)

; Attribute selector brackets
(attribute_selector "[" @punctuation.bracket)
(attribute_selector "]" @punctuation.bracket)
