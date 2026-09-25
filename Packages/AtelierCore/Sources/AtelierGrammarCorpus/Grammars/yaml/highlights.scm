(boolean_scalar) @boolean

(null_scalar) @constant.builtin

[
  (double_quote_scalar)
  (single_quote_scalar)
  (block_scalar)
  (string_scalar)
] @string

[
  (integer_scalar)
  (float_scalar)
] @number

(comment) @comment

[
  (anchor_name)
  (alias_name)
] @label

(tag) @type

[
  (yaml_directive)
  (tag_directive)
  (reserved_directive)
] @attribute

(block_mapping_pair
  key: (flow_node
    [
      (double_quote_scalar)
      (single_quote_scalar)
    ] @property))

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @property)))

(flow_mapping
  (_
    key: (flow_node
      [
        (double_quote_scalar)
        (single_quote_scalar)
      ] @property)))

(flow_mapping
  (_
    key: (flow_node
      (plain_scalar
        (string_scalar) @property))))

[
  ","
  "-"
  ":"
  ">"
  "?"
  "|"
] @punctuation.delimiter

[
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

[
  "*"
  "&"
  "---"
  "..."
] @punctuation.special

; Merge key (<<)
(
  (block_mapping_pair
    key: (flow_node
      (plain_scalar
        (string_scalar) @keyword))
    (#eq? @keyword "<<")))

; Escape sequences in double-quoted strings
(escape_sequence) @string.escape

; Document and stream nodes (structural only)
(document) @none
(stream) @none

; Block sequence items (structural only)
(block_sequence_item) @none

; Flow sequence
(flow_sequence) @none
(flow_sequence "," @punctuation.delimiter)
(flow_sequence "[" @punctuation.bracket)
(flow_sequence "]" @punctuation.bracket)

; Flow mapping delimiters
(flow_mapping "," @punctuation.delimiter)
(flow_mapping "{" @punctuation.bracket)
(flow_mapping "}" @punctuation.bracket)

; Explicit key indicator
(block_mapping_pair "?" @punctuation.special)

; Block scalar values
(block_scalar) @string
