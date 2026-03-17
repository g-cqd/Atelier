;From nvim-treesitter/nvim-treesitter
(atx_heading
  (inline) @text.title)

(setext_heading
  (paragraph) @text.title)

[
  (atx_h1_marker)
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
  (setext_h1_underline)
  (setext_h2_underline)
] @punctuation.special

[
  (link_title)
  (indented_code_block)
  (fenced_code_block)
] @text.literal

(fenced_code_block_delimiter) @punctuation.delimiter

(code_fence_content) @none

(link_destination) @text.uri

(link_label) @text.reference

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (thematic_break)
] @punctuation.special

[
  (block_continuation)
  (block_quote_marker)
] @punctuation.special

(backslash_escape) @string.escape

; Emphasis and strong
(emphasis) @text.emphasis
(strong_emphasis) @text.strong

; Inline code
(code_span) @text.literal

; Task list markers
(task_list_marker_checked) @constant.builtin
(task_list_marker_unchecked) @punctuation.special

; Info string on fenced code blocks
(info_string) @label

; Images
(image (image_description) @text.reference)
(image (link_destination) @text.uri)

; Inline links
(inline_link (link_text) @text.reference)
(inline_link (link_destination) @text.uri)

; Shortcut links
(shortcut_link) @text.reference

; HTML blocks inside markdown
(html_block) @none

; Paragraph (structural, no highlight)
(paragraph) @none

; GFM table elements
(pipe_table_header) @text.title
(pipe_table_delimiter_row) @punctuation.special
(pipe_table_delimiter_cell) @punctuation.special
