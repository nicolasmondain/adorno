#!/usr/bin/env python3
"""Validates JSON Lines files against a JSON Schema, with the standard library only.

Usage: jsonschema_subset.py SCHEMA FILE.jsonl…
Only the keywords the journal schema uses are implemented; a schema using any other is refused (exit 2) rather than
half-checked. Prints `file:line: problem` for each invalid line; exit 1 if there is one.
"""
import json
import re
import sys

ANNOTATIONS = {"$schema", "title", "description"}
TYPES = {"string": str, "integer": int, "number": (int, float), "boolean": bool, "object": dict, "array": list,
         "null": type(None)}


def is_type(value, name):
    if isinstance(value, bool) and name in ("integer", "number"):
        return False
    return isinstance(value, TYPES[name])


def check(value, schema, where="event"):
    """The problems of value against schema, as a list of strings."""
    out = []
    for keyword, want in schema.items():
        if keyword in ANNOTATIONS or keyword == "then":
            continue
        if keyword == "type":
            names = want if isinstance(want, list) else [want]
            if not any(is_type(value, n) for n in names):
                out.append(f"{where}: expected {' or '.join(names)}")
        elif keyword == "const":
            if value != want:
                out.append(f"{where}: expected {want!r}")
        elif keyword == "enum":
            if value not in want:
                out.append(f"{where}: {value!r} is not one of {want}")
        elif keyword == "pattern":
            if isinstance(value, str) and not re.search(want, value):
                out.append(f"{where}: {value!r} does not match {want}")
        elif keyword == "minimum":
            if is_type(value, "number") and value < want:
                out.append(f"{where}: {value} is below {want}")
        elif keyword == "required":
            if isinstance(value, dict):
                out += [f"{where}: missing '{k}'" for k in want if k not in value]
        elif keyword == "properties":
            if isinstance(value, dict):
                for k, sub in want.items():
                    if k in value:
                        out += check(value[k], sub, f"{where}.{k}")
        elif keyword == "additionalProperties":
            if want is False and isinstance(value, dict):
                out += [f"{where}: unknown field '{k}'" for k in value if k not in schema.get("properties", {})]
        elif keyword == "items":
            if isinstance(value, list):
                for i, item in enumerate(value):
                    out += check(item, want, f"{where}[{i}]")
        elif keyword == "allOf":
            for sub in want:
                out += check(value, sub, where)
        elif keyword == "if":
            if not check(value, want, where):
                out += check(value, schema.get("then", {}), where)
        else:
            raise NotImplementedError(f"schema keyword '{keyword}' is not supported by this checker")
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[0], encoding="utf-8") as f:
        schema = json.load(f)
    bad = 0
    for path in argv[1:]:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                try:
                    problems = check(json.loads(line), schema)
                except ValueError as e:
                    problems = [f"not JSON ({e})"]
                except NotImplementedError as e:
                    print(e, file=sys.stderr)
                    return 2
                for p in problems:
                    bad += 1
                    print(f"{path}:{n}: {p}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
