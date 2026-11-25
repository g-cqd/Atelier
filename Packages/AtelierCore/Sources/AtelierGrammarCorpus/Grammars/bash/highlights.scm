[
  (string)
  (raw_string)
  (heredoc_body)
  (heredoc_start)
] @string

(command_name) @function

(variable_name) @property

[
  "case"
  "do"
  "done"
  "elif"
  "else"
  "esac"
  "export"
  "fi"
  "for"
  "function"
  "if"
  "in"
  "select"
  "then"
  "unset"
  "until"
  "while"
] @keyword

(comment) @comment

(function_definition name: (word) @function)

(file_descriptor) @number

[
  (command_substitution)
  (process_substitution)
  (expansion)
]@embedded

[
  "$"
  "&&"
  ">"
  ">>"
  "<"
  "|"
] @operator

(
  (command (_) @constant)
  (#match? @constant "^-")
)

; Additional keywords
[
  "return"
  "local"
  "declare"
  "typeset"
  "readonly"
  "shift"
  "set"
  "eval"
  "exec"
  "trap"
  "wait"
  "break"
  "continue"
] @keyword

; Special variables
(
  (simple_expansion (special_variable_name) @variable.builtin)
)
(
  (simple_expansion (variable_name) @variable)
)

; Builtin commands
(
  (command_name (word) @function.builtin)
  (#any-of? @function.builtin "echo" "printf" "cd" "pwd" "test" "read" "source" "exit" "true" "false" "type" "hash" "alias" "unalias" "bg" "fg" "jobs" "kill" "umask" "getopts" "pushd" "popd" "dirs" "let" "mapfile" "readarray" "compgen" "complete" "compopt")
)

; Additional operators
"||" @operator
"!" @operator
"&" @operator

; Redirections
(file_redirect destination: (word) @string)
(heredoc_redirect (heredoc_start) @string.special)

; Arithmetic expansion
(arithmetic_expansion) @number

; Test brackets
"[" @punctuation.bracket
"]" @punctuation.bracket
"[[" @punctuation.bracket
"]]" @punctuation.bracket

; Regex patterns
(regex) @string.special

; Punctuation
";" @punctuation.delimiter

; Subshell delimiters
"(" @punctuation.bracket
")" @punctuation.bracket

; Variable assignment
(variable_assignment name: (variable_name) @variable)
(variable_assignment "=" @operator)

; String interpolation
(string (simple_expansion (variable_name) @variable))
(string (expansion (variable_name) @variable))
