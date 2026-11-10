#!/usr/bin/env python3
"""Check the loaded content's block class chains against their templates.

Reads the game's merged content tables
(`<game>/.horizon-cache/mod-content/block-behaviours.json`) and the carried
declarations, and asserts every declared block copies its template's Java
class chain (which is what gives it the template's placement, interaction and
tick behaviour). Called by tools/e2e.sh.

Usage: class_check.py <block-behaviours.json> <content/data/mcwpaths/horizon/block>
"""
import glob
import json
import os
import sys


def main():
    behaviours_path, decl_dir = sys.argv[1:]
    with open(behaviours_path) as handle:
        table = json.load(handle)
    classes = {
        entry["name"]: entry.get("class")
        for entry in table.get("blocks", [])
        if "name" in entry
    }
    decls = {}
    for path in glob.glob(os.path.join(decl_dir, "*.json")):
        decls[os.path.basename(path)[:-5]] = json.load(open(path))
    missing = []
    differ = []
    for name, decl in sorted(decls.items()):
        full = f"mcwpaths:{name}"
        if full not in classes:
            missing.append(full)
            continue
        template = decl["template"]
        if template not in classes:
            missing.append(template)
            continue
        if classes[full] != classes[template]:
            differ.append(
                f"{full}: {classes[full]} != {template}'s {classes[template]}"
            )
    print(f"declared blocks: {len(decls)}, class chains checked: {len(classes)}")
    if missing:
        print(f"FAIL: no class row for {missing[:8]}", file=sys.stderr)
        return 1
    if differ:
        print("FAIL: class chains differ from the template:", file=sys.stderr)
        for line in differ[:8]:
            print(f"  {line}", file=sys.stderr)
        return 1
    print(
        f"PASS: all {len(decls)} declared blocks copy their template's class "
        "chain (placement, interaction and tick behaviour)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
