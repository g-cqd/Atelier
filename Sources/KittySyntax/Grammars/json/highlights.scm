(pair
  key: (_) @string.special.key)

(string) @string

(number) @number

[
  (null)
  (true)
  (false)
] @constant.builtin

(escape_sequence) @escape

(comment) @comment

; Punctuation delimiters
"," @punctuation.delimiter
":" @punctuation.delimiter

; Bracket punctuation
"[" @punctuation.bracket
"]" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket

; Typed array items
(array (number) @number)
(array (string) @string)

; Container nodes (no highlight, structural only)
(object) @none
(array) @none

; Document root
(document) @none
