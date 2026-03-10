#!/usr/bin/env bash
# generate-grammars.sh
#
# Clones tree-sitter-{language} repositories and extracts grammar.json and
# highlights.scm into the KittySyntax bundle resource directory.
#
# Usage:
#   ./Scripts/generate-grammars.sh <language>
#   ./Scripts/generate-grammars.sh all
#
# Examples:
#   ./Scripts/generate-grammars.sh swift
#   ./Scripts/generate-grammars.sh javascript
#   ./Scripts/generate-grammars.sh all
#
# The script clones each repo into a temporary directory, copies the two files,
# then removes the clone. Re-running for the same language overwrites the
# existing files, making it safe to use for updates.
#
# Requirements:
#   - git must be on PATH
#   - Run from the package root (the directory containing Package.swift)

set -euo pipefail

GRAMMARS_DIR="Sources/KittySyntax/Grammars"

# All 20 languages listed in languages.json
ALL_LANGUAGES=(
  json swift javascript typescript python rust go
  c cpp html css bash ruby java kotlin lua toml yaml markdown
)

# Some tree-sitter repos deviate from the standard naming convention.
# Map language name -> repo name when they differ.
declare -A REPO_OVERRIDES=(
  [cpp]="tree-sitter-cpp"
  [bash]="tree-sitter-bash"
  [markdown]="tree-sitter-markdown"
)

repo_name_for() {
  local lang="$1"
  if [[ -v REPO_OVERRIDES[$lang] ]]; then
    echo "${REPO_OVERRIDES[$lang]}"
  else
    echo "tree-sitter-${lang}"
  fi
}

clone_url_for() {
  local lang="$1"
  echo "https://github.com/tree-sitter/$(repo_name_for "$lang").git"
}

generate_language() {
  local lang="$1"
  local dest="${GRAMMARS_DIR}/${lang}"
  local clone_dir
  clone_dir="$(mktemp -d)"

  echo "==> Generating grammar for: ${lang}"
  echo "    Cloning $(clone_url_for "$lang") ..."

  # Shallow clone to keep download size small
  if ! git clone --depth 1 --quiet "$(clone_url_for "$lang")" "${clone_dir}"; then
    echo "    ERROR: Failed to clone repository for '${lang}'. Skipping." >&2
    rm -rf "${clone_dir}"
    return 1
  fi

  mkdir -p "${dest}"

  # Copy grammar.json — required
  if [[ -f "${clone_dir}/grammar.json" ]]; then
    cp "${clone_dir}/grammar.json" "${dest}/grammar.json"
    echo "    Copied grammar.json"
  else
    echo "    WARNING: grammar.json not found in repo root. Skipping copy." >&2
  fi

  # Copy highlights.scm — optional (not all repos include one)
  local scm_candidates=(
    "${clone_dir}/queries/highlights.scm"
    "${clone_dir}/queries/local.scm"
    "${clone_dir}/highlights.scm"
  )
  local scm_copied=false
  for candidate in "${scm_candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      cp "${candidate}" "${dest}/highlights.scm"
      echo "    Copied highlights.scm (from ${candidate##*/clone_dir/})"
      scm_copied=true
      break
    fi
  done
  if [[ "${scm_copied}" == false ]]; then
    echo "    WARNING: No highlights.scm found for '${lang}'. Manual authoring required."
  fi

  rm -rf "${clone_dir}"
  echo "    Done: ${dest}"
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <language|all>" >&2
    exit 1
  fi

  # Ensure we are running from the package root
  if [[ ! -f "Package.swift" ]]; then
    echo "ERROR: Run this script from the package root (the directory containing Package.swift)." >&2
    exit 1
  fi

  local arg="$1"
  local failed=()

  if [[ "${arg}" == "all" ]]; then
    for lang in "${ALL_LANGUAGES[@]}"; do
      generate_language "${lang}" || failed+=("${lang}")
    done
  else
    generate_language "${arg}" || failed+=("${arg}")
  fi

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo ""
    echo "The following languages failed to generate:" >&2
    for lang in "${failed[@]}"; do
      echo "  - ${lang}" >&2
    done
    exit 1
  fi

  echo ""
  echo "Grammar generation complete."
}

main "$@"
