#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentui-reference-compare.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

bun "$repo_dir/reference/run_reference_parser.ts" \
  < "$repo_dir/reference/terminal_vectors.tsv" \
  > "$temp_dir/reference"

nix develop "$repo_dir#test" -c dune exec --root "$repo_dir" \
  ./reference/parse_terminal_vectors.exe \
  < "$repo_dir/reference/terminal_vectors.tsv" \
  > "$temp_dir/ocaml"

diff -u "$temp_dir/reference" "$temp_dir/ocaml"
