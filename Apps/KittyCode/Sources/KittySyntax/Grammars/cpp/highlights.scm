; Functions

(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (qualified_identifier
    name: (identifier) @function.call))

(call_expression
  function: (field_expression
    field: (field_identifier) @function.call))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

(function_declarator
  declarator: (identifier) @function)

; Types

(type_identifier) @type
(primitive_type) @type.builtin
(sized_type_specifier) @type

((namespace_identifier) @type
 (#match? @type "^[A-Z]"))

(auto) @type

; Constants

(this) @variable.builtin
(null "nullptr" @constant.builtin)

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

; Identifiers

(identifier) @variable
(field_identifier) @property

; Modules
(module_name
  (identifier) @namespace)

; Keywords

[
 "break" "case" "catch" "class" "co_await" "co_return" "co_yield"
 "const" "constexpr" "constinit" "consteval" "continue" "default"
 "delete" "do" "else" "enum" "explicit" "extern" "final" "for"
 "friend" "goto" "if" "inline" "mutable" "namespace" "new"
 "noexcept" "override" "private" "protected" "public" "return"
 "sizeof" "static" "struct" "switch" "template" "throw" "try"
 "typedef" "typename" "union" "using" "concept" "requires"
 "virtual" "volatile" "while" "import" "export" "module"
] @keyword

; Operators

[
  "--" "-" "-=" "->" "=" "!=" "*" "&" "&&" "+" "++" "+="
  "<" "==" ">" "||" "|" "^" "~" "%" "%=" "*=" "/=" "/"
  "<<" "<<=" ">>" ">>=" "&=" "|=" "^=" "<=" ">=" "!"
  "?" "::" "<=>"
] @operator

; Punctuation

[
  "(" ")" "[" "]" "{" "}"
  "<" ">"
] @punctuation.bracket

[
  "." ";" "," ":"
] @punctuation.delimiter

; Strings

(string_literal) @string
(raw_string_literal) @string
(char_literal) @string
(escape_sequence) @string.escape

; Numbers

(number_literal) @number

[
  (true)
  (false)
] @boolean

(null "nullptr" @constant.builtin)

; Comments

(comment) @comment
