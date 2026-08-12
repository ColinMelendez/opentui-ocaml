#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
reference_dir="$repo_dir/packages/opentui-core/reference"
manifest="$reference_dir/perf_manifest.tsv"
temp_root=$(printenv TMPDIR 2>/dev/null || true)
if [ -z "$temp_root" ]; then
  temp_root=/tmp
fi
temp_dir=$(mktemp -d "$temp_root/opentui-performance-compare.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

bun "$reference_dir/run_terminal_perf.ts" "$manifest" \
  > "$temp_dir/bun.tsv"

nix develop "$repo_dir#test" -c dune exec --root "$repo_dir" \
  ./packages/opentui-core/reference/benchmark_terminal.exe -- "$manifest" \
  > "$temp_dir/ocaml.tsv"

awk -F '\t' '$1 != "case" && $1 !~ /^#/ { print }' \
  "$temp_dir/ocaml.tsv" > "$temp_dir/ocaml-rows.tsv"
awk -F '\t' '$1 != "case" && $1 !~ /^#/ { print }' \
  "$temp_dir/bun.tsv" > "$temp_dir/bun-rows.tsv"
awk -F '\t' '{ print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 }' \
  "$temp_dir/ocaml-rows.tsv" > "$temp_dir/ocaml-shape.tsv"
awk -F '\t' '{ print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 }' \
  "$temp_dir/bun-rows.tsv" > "$temp_dir/bun-shape.tsv"
diff -u "$temp_dir/ocaml-shape.tsv" "$temp_dir/bun-shape.tsv"

awk '/^# schema_version=|^# warmup_batches=/{ print }' "$temp_dir/ocaml.tsv" \
  > "$temp_dir/ocaml-protocol.tsv"
awk '/^# schema_version=|^# warmup_batches=/{ print }' "$temp_dir/bun.tsv" \
  > "$temp_dir/bun-protocol.tsv"
diff -u "$temp_dir/ocaml-protocol.tsv" "$temp_dir/bun-protocol.tsv"

manifest_hash_command=sha256sum
if ! command -v "$manifest_hash_command" >/dev/null 2>&1; then
  manifest_hash_command=shasum
  manifest_hash=$($manifest_hash_command -a 256 "$manifest" | awk '{print $1}')
else
  manifest_hash=$($manifest_hash_command "$manifest" | awk '{print $1}')
fi

printf '%s\n' "terminal performance comparison (diagnostic; timing ratios are not a gate)"
printf '%s\n' "manifest_sha256=$manifest_hash"
printf 'case\tOCaml median ns/op\tBun median ns/op\tOCaml p95 ns/op\tBun p95 ns/op\tOCaml RSD ppm\tBun RSD ppm\n'
awk -F '\t' '
  FNR == NR {
    if ($1 in bun_median) exit 2
    bun_median[$1] = $9
    bun_p95[$1] = $10
    bun_rsd[$1] = $11
    next
  }
  {
    if (!($1 in bun_median)) exit 3
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $9, bun_median[$1], $10, bun_p95[$1], $11, bun_rsd[$1]
  }
' "$temp_dir/bun-rows.tsv" "$temp_dir/ocaml-rows.tsv"

printf '%s\n' "allocation diagnostics are not equivalent rates: OCaml reports timed GC words/collections; Bun reports retained post-GC heap and ArrayBuffer deltas."
