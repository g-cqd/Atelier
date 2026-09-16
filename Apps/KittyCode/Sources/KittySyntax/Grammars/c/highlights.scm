(identifier) @variable

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

; Keywords

[
  "break" "case" "const" "continue" "default" "do" "else"
  "enum" "extern" "for" "if" "inline" "return" "sizeof"
  "static" "struct" "switch" "typedef" "union" "volatile" "while"
  "register" "restrict" "_Atomic" "_Bool" "_Complex"
] @keyword

[
  "#define" "#elif" "#else" "#endif" "#if" "#ifdef"
  "#ifndef" "#include" "#pragma" "#undef"
] @keyword
(preproc_directive) @keyword

; Operators

[
  "--" "-" "-=" "->" "=" "!=" "*" "&" "&&" "+" "++" "+="
  "<" "==" ">" "||" "|" "^" "~" "%" "%=" "*=" "/=" "/""
  "<<" "<<=" ">>" ">>=" "&=" "|=" "^=" "<=" ">=" "!"
  "?" ":"
] @operator

; Punctuation

[
  "(" ")" "[" "]" "{" "}"
] @punctuation.bracket

[
  "." ";" ","
] @punctuation.delimiter

; Literals

(string_literal) @string
(system_lib_string) @string
(char_literal) @string
(escape_sequence) @string.escape

(null) @constant.builtin
(number_literal) @number

[
  (true)
  (false)
] @boolean

; Types

(field_identifier) @property
(statement_identifier) @label
(type_identifier) @type
(primitive_type) @type.builtin
(sized_type_specifier) @type

; Functions

(call_expression
  function: (identifier) @function.call)
(call_expression
  function: (field_expression
    field: (field_identifier) @function.call))
(function_declarator
  declarator: (identifier) @function)
(preproc_function_def
  name: (identifier) @function.special)

(comment) @comment
