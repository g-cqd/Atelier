(tag_name) @tag
(erroneous_end_tag_name) @tag.error
(doctype) @constant
(attribute_name) @attribute
(attribute_value) @string
(comment) @comment

[
  "<"
  ">"
  "</"
  "/>"
] @punctuation.bracket

; Quoted attribute values
(quoted_attribute_value) @string

; Tag names in elements
(element (start_tag (tag_name) @tag))
(element (end_tag (tag_name) @tag))
(self_closing_tag (tag_name) @tag)

; Entities and plain text
(entity) @string.escape
(text) @none

; Assignment operator
"=" @operator

; Embedded script and style
(script_element (start_tag (tag_name) @tag))
(script_element (raw_text) @embedded)
(style_element (start_tag (tag_name) @tag))
(style_element (raw_text) @embedded)

; Attributes
(attribute (attribute_name) @attribute)
(attribute (quoted_attribute_value) @string)

; DOCTYPE keywords
"<!DOCTYPE" @keyword
"<!doctype" @keyword

; Bracket punctuation in tags
(start_tag ">" @punctuation.bracket)
(end_tag ">" @punctuation.bracket)
(self_closing_tag "/>" @punctuation.bracket)
(start_tag "<" @punctuation.bracket)
(end_tag "</" @punctuation.bracket)

; ARIA attributes
((attribute_name) @attribute
 (#match? @attribute "^aria-"))

; Data attributes
((attribute_name) @attribute
 (#match? @attribute "^data-"))

; Boolean attributes
((attribute_name) @constant
 (#any-of? @constant "hidden" "disabled" "checked" "readonly" "required" "selected" "autofocus" "autoplay" "controls" "loop" "muted" "defer" "async" "novalidate" "multiple" "open"))

; Event handler attributes
((attribute_name) @function
 (#match? @attribute "^on"))

; Void/meta elements
(start_tag
  (tag_name) @keyword
  (#any-of? @keyword "meta" "link" "base"))

; Void self-closing tags
(self_closing_tag
  (tag_name) @tag)

; Fragment root
(fragment) @none
