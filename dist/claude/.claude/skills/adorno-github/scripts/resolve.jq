# Resolves the settings of one repo from the registry (repos.json). Input: the registry. Args: --arg r owner/repo.
# Output: the merged settings, or nothing when no scope declares the repo (callers treat that as "unregistered").
#
# Layers, weakest first (each layer's `use: [preset…]` is expanded before its own keys):
#   defaults  →  every workspace whose `repos` globs match (file order)  →  every `repos` key that is a glob and
#   matches (least specific first)  →  the exact `repos` key.
# Merge: objects merge key by key, arrays and scalars are replaced, except `context` and `vision`, which accumulate.
# Shared by adorno-github/scripts/_lib.sh and bin/kit (kit conf, kit install): keep it the single source of truth.

def glob_re: "^" + (gsub("(?<c>[.+?^${}()|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*\\*"; "\u0001") | gsub("\\*"; "[^/]*")
  | gsub("\u0001"; ".*")) + "$";

def accumulating: ["context", "vision"];

def uniq_keep_order: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);

# merge2(a; b): b over a
def merge2($a; $b):
  reduce ($b | to_entries[] | select(.value != null)) as $e ($a;
    if (accumulating | index([$e.key])) and ($e.value | type) == "array"
      then .[$e.key] = ((.[$e.key] // []) + $e.value | uniq_keep_order)
    elif (.[$e.key] | type) == "object" and ($e.value | type) == "object"
      then .[$e.key] = (.[$e.key] * $e.value)
    else .[$e.key] = $e.value end);

# a layer with its presets expanded (presets may use presets; kit check refuses cycles)
def expand($presets):
  . as $layer
  | reduce (($layer.use // [])[]) as $u ({};
      merge2(.; ($presets[$u] // error("unknown preset: \($u)")) | expand($presets)))
  | merge2(.; $layer | del(.use, .repos, .paths));

. as $reg
| ($reg.presets // {}) as $presets
| [($reg.workspaces // {}) | to_entries[]
    | select(any((.value.repos // [])[]; . as $g | $r | test($g | glob_re)))
    | {scope: "workspace:\(.key)", layer: .value}] as $ws
| [($reg.repos // {}) | to_entries[]
    | .key as $k | select(($k | contains("*")) and ($r | test($k | glob_re)))
    | {scope: "repos:\(.key)", layer: .value, weight: (.key | gsub("\\*"; "") | length)}]
  | sort_by(.weight) as $globs
| [($reg.repos // {})[$r] | select(. != null) | {scope: "repos:\($r)", layer: .}] as $exact
| ($ws + $globs + $exact) as $layers
| select($layers | length > 0)
| reduce $layers[] as $l (($reg.defaults // {}) | expand($presets); merge2(.; $l.layer | expand($presets)))
| .repo = $r
| .scopes = ["defaults"] + [$layers[].scope]
