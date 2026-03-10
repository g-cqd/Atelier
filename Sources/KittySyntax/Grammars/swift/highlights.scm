; Keywords
[
  "import" "struct" "class" "enum" "func" "var" "let"
  "guard" "if" "else" "switch" "case" "return" "default"
  "for" "while" "in" "do" "catch" "try" "throw" "throws"
  "protocol" "extension" "typealias" "where"
  "public" "private" "internal" "fileprivate" "open"
  "static" "final" "override" "mutating"
  "init" "deinit" "self" "super"
  "async" "await" "some" "any"
  "break" "continue" "fallthrough" "defer" "repeat"
  "as" "is" "nil" "true" "false"
  "weak" "unowned" "lazy" "inout"
  "convenience" "required" "dynamic" "optional" "indirect"
  "nonisolated" "consuming" "borrowing"
] @keyword

; Types
(type_identifier) @type

; Strings
(line_string_literal) @string

; Numbers
(integer_literal) @number
(real_literal) @number

; Comments
(comment) @comment
(multiline_comment) @comment

; Attributes
(attribute) @attribute

; Function declarations
(function_declaration name: (simple_identifier) @function)

; Property declarations
(property_declaration pattern: (pattern) @variable)

; Parameters
(parameter name: (simple_identifier) @variable.parameter)
