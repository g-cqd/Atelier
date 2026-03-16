; Types

(type_identifier) @type
(predefined_type) @type.builtin

((identifier) @type
 (#match? @type "^[A-Z]"))

(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

; Variables

(required_parameter (identifier) @variable.parameter)
(optional_parameter (identifier) @variable.parameter)

(identifier) @variable

; Function definitions

(function_declaration
  name: (identifier) @function)

(method_definition
  name: (property_identifier) @function.method)

(variable_declarator
  name: (identifier) @function
  value: [(function_expression) (arrow_function)])

; Function calls

(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (member_expression
    property: (property_identifier) @function.method))

; Properties

(property_identifier) @property

; Special identifiers

(this) @variable.builtin

[
  (true)
  (false)
  (null)
  (undefined)
] @constant.builtin

; Literals

(comment) @comment
[
  (string)
  (template_string)
] @string
(regex) @string.special
(number) @number

; Operators

[
  "-" "--" "-=" "+" "++" "+=" "*" "*=" "**" "**="
  "/" "/=" "%" "%=" "<" "<=" "<<" "<<=" "=" "=="
  "===" "!" "!=" "!==" "=>" ">" ">=" ">>" ">>="
  ">>>" ">>>=" "~" "^" "&" "|" "^=" "&=" "|="
  "&&" "||" "??" "&&=" "||=" "??="
] @operator

; Punctuation

[
  "(" ")" "[" "]" "{" "}"
] @punctuation.bracket

[
  ";" "." "," (optional_chain)
] @punctuation.delimiter

(template_substitution
  "${" @punctuation.special
  "}" @punctuation.special) @embedded

; Keywords

[ "abstract"
  "declare"
  "enum"
  "export"
  "implements"
  "interface"
  "keyof"
  "namespace"
  "private"
  "protected"
  "public"
  "type"
  "readonly"
  "override"
  "satisfies"
  "as"
  "async"
  "await"
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "debugger"
  "default"
  "delete"
  "do"
  "else"
  "extends"
  "finally"
  "for"
  "from"
  "function"
  "get"
  "if"
  "import"
  "in"
  "instanceof"
  "let"
  "new"
  "of"
  "return"
  "set"
  "static"
  "switch"
  "target"
  "throw"
  "try"
  "typeof"
  "var"
  "void"
  "while"
  "with"
  "yield"
] @keyword
