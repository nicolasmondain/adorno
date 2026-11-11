# Resolves the settings of one repo from the registry (repos.json). Input: the registry. Args: --arg r owner/repo.
# Output: the merged settings, or nothing when no scope declares the repo (callers treat that as "unregistered").
#
# Layers, weakest first (each layer's `use: [preset…]` is expanded before its own keys):
#   defaults  →  every workspace whose `repos` globs match (file order)  →  every `repos` key that is a glob and
#   matches (least specific first)  →  the exact `repos` key.
# Merge: objects merge key by key, arrays and scalars are replaced, except `context` and `vision`, which accumulate,
# and `permissions`, whose lists (`deny`, `claude.allow|ask|deny`) accumulate too: a more specific scope can add a
# restriction, never silently drop one. Repo names match case-insensitively, as on GitHub.
# `areas` and `fallbacks` merge per area (and per sub-area under `sub`): `paths`, `content` and single roles (`build`,
# `fix`, `perf`, `qa`) are replaced; list roles (`review`, `skills`) accumulate, and an entry `-x` in the newer layer
# removes `x` (the markers never appear in the result). Once every layer is merged, each sub-area inherits its parent's
# roles: single role = its own else the parent's, list = parent's + its own; `paths` and `content` are not inherited.
# Shared by adorno-github/scripts/_lib.sh and bin/kit (kit conf, kit install): keep it the single source of truth.

def glob_re: "^" + (gsub("(?<c>[.+?^${}()|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*\\*"; "\u0001") | gsub("\\*"; "[^/]*")
  | gsub("\u0001"; ".*")) + "$";

def accumulating: ["context", "vision"];

def uniq_keep_order: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);

def union($x; $y): (($x // []) + ($y // [])) | uniq_keep_order;

def merge_permissions($a; $b):
  ($a * ($b | del(.deny, .claude)))
  | .deny = union($a.deny; $b.deny)
  | .claude = (reduce ("allow", "ask", "deny") as $k
      ((($a.claude // {}) * (($b.claude // {}) | del(.allow, .ask, .deny)));
       .[$k] = union($a.claude[$k]; $b.claude[$k])));

def list_roles: ["review", "skills"];

# a list of an area: union of both layers, then every `-x` of the newer layer removes `x`
def merge_list($a; $b):
  ($b // []) as $nb
  | ([$nb[] | select(type == "string" and startswith("-")) | .[1:]]) as $drop
  | union($a; $nb) | map(select(type != "string" or (startswith("-") | not)) | select(. as $x | $drop | index([$x]) | not));

# one area (or sub-area, or `always`, or a fallback): lists accumulate, everything else is replaced
def merge_area($a; $b):
  if ($a | type) != "object" or ($b | type) != "object" then $b
  else reduce ($b | to_entries[] | select(.value != null)) as $e ($a;
    if $e.key == "sub" and ($e.value | type) == "object"
      then .sub = reduce ($e.value | to_entries[] | select(.value != null)) as $s (.sub // {}; .[$s.key] = merge_area(.[$s.key]; $s.value))
    elif (list_roles | index([$e.key])) and ($e.value | type) == "array"
      then .[$e.key] = merge_list(.[$e.key]; $e.value)
    else .[$e.key] = $e.value end)
  end;

def merge_areas($a; $b):
  if ($b | type) != "object" then $b
  else reduce ($b | to_entries[] | select(.value != null)) as $e (($a | if type == "object" then . else {} end);
    .[$e.key] = merge_area(.[$e.key]; $e.value))
  end;

# once every layer is merged, no `-x` marker may remain (an area absent from the lower layers keeps its own)
def strip_markers:
  walk(if type == "object"
    then reduce list_roles[] as $r (.; if (.[$r] | type) == "array" then .[$r] |= map(select(type != "string" or (startswith("-") | not))) else . end)
    else . end);

# the sub-areas of an area take the roles of their parent
def inherit_roles:
  if type != "object" then .
  else with_entries(
    .value as $p
    | if ($p | type) == "object" and ($p.sub | type) == "object" then
        .value.sub |= with_entries(.value |= (
          . as $s
          | reduce ("build", "fix", "perf", "qa") as $r ($s; if $s[$r] == null and $p[$r] != null then .[$r] = $p[$r] else . end)
          | reduce list_roles[] as $r (.; if ($p[$r] // []) + ($s[$r] // []) | length > 0 then .[$r] = union($p[$r]; $s[$r]) else . end)))
      else . end)
  end;

# merge2(a; b): b over a
def merge2($a; $b):
  reduce ($b | to_entries[] | select(.value != null)) as $e ($a;
    if ($e.key == "areas" or $e.key == "fallbacks") and ($e.value | type) == "object"
      then .[$e.key] = merge_areas(.[$e.key]; $e.value)
    elif $e.key == "permissions" and ($e.value | type) == "object"
      then .permissions = merge_permissions(.permissions // {}; $e.value)
    elif (accumulating | index([$e.key])) and ($e.value | type) == "array"
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
| ($r | ascii_downcase) as $lr
| ($reg.presets // {}) as $presets
| [($reg.workspaces // {}) | to_entries[]
    | select(any((.value.repos // [])[]; . as $g | $lr | test($g | ascii_downcase | glob_re)))
    | {scope: "workspace:\(.key)", layer: .value}] as $ws
| [($reg.repos // {}) | to_entries[]
    | .key as $k | select(($k | contains("*")) and ($lr | test($k | ascii_downcase | glob_re)))
    | {scope: "repos:\(.key)", layer: .value, weight: (.key | gsub("\\*"; "") | length)}]
  | sort_by(.weight) as $globs
| [($reg.repos // {}) | to_entries[] | select((.key | contains("*") | not) and (.key | ascii_downcase) == $lr)
    | {scope: "repos:\(.key)", layer: .value}] as $exact
| ($ws + $globs + $exact) as $layers
| select($layers | length > 0)
| reduce $layers[] as $l (($reg.defaults // {}) | expand($presets); merge2(.; $l.layer | expand($presets)))
| (if .areas then .areas |= (strip_markers | inherit_roles) else . end)
| (if .fallbacks then .fallbacks |= strip_markers else . end)
| .repo = $r
| .scopes = ["defaults"] + [$layers[].scope]
