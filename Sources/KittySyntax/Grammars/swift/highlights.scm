; Keywords
[
  "import" "struct" "class" "enum" "func" "var" "let"
  "guard" "if" "else" "switch" "case" "return" "default"
  "for" "while" "in" "do" "catch" "try" "throw" "throws"
  "protocol" "extension" "typealias" "where"
  "public" "private" "internal" "fileprivate" "open"
  "static" "final" "override" "mutating"
  "init" "deinit" "super"
  "async" "await" "some" "any"
  "break" "continue" "fallthrough" "defer" "repeat"
  "as" "is"
  "weak" "unowned" "lazy" "inout"
  "convenience" "required" "dynamic" "optional" "indirect"
  "nonisolated" "consuming" "borrowing"
  "associatedtype" "operator" "precedencegroup"
  "rethrows" "subscript" "didSet" "willSet" "get" "set"
] @keyword

; Boolean literals
[
  "true"
  "false"
] @boolean

; Nil
"nil" @constant.builtin

; Self / self
"self" @variable.builtin
"Self" @type.builtin

; Types
(type_identifier) @type

; Strings
(line_string_literal) @string
(multi_line_string_literal) @string

; String interpolation
(interpolated_expression
  "\\" @punctuation.special
  "(" @punctuation.special
  ")" @punctuation.special) @embedded

; String escape sequences
(escape_sequence) @string.escape

; Numbers
(integer_literal) @number
(real_literal) @number.float
(hex_literal) @number
(oct_literal) @number
(bin_literal) @number

; Comments
(comment) @comment
(multiline_comment) @comment

; Doc comments
((comment) @comment.documentation
 (#match? @comment.documentation "^///"))
((multiline_comment) @comment.documentation
 (#match? @comment.documentation "^/\\*\\*"))

; Attributes
(attribute) @attribute

; Function declarations
(function_declaration name: (simple_identifier) @function)

; Function calls
(call_expression
  (simple_identifier) @function.call)

; Method calls
(call_expression
  (navigation_expression
    suffix: (simple_identifier) @function.method))

; Property declarations
(property_declaration pattern: (pattern) @variable)

; Parameters
(parameter name: (simple_identifier) @variable.parameter)

; Operators
[
  "+"  "-"  "*"  "/"  "%"
  "="  "+=" "-=" "*=" "/=" "%="
  "==" "!=" "<" ">" "<=" ">="
  "&&" "||" "!"
  "??" "?"
  "&" "|" "^" "~"
  "<<" ">>"
  "..<" "..."
  "->"
] @operator

; Punctuation - brackets
[
  "(" ")"
  "[" "]"
  "{" "}"
] @punctuation.bracket

; Punctuation - delimiters
[
  "." "," ":" ";"
] @punctuation.delimiter

; Labels
(statement_label) @label

; Property access
(navigation_expression
  suffix: (simple_identifier) @property)
