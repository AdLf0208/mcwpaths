#!/usr/bin/env python3
"""Write the 26.3 block declarations for the carried mcwpaths content.

The raw `horizon-port-pack carry` (no NeoForge oracle) guesses a template from
the blockstate's property *names* and emits `{"template": ...}` only. For this
mod that is wrong in three ways:

* the 52 `EngravedBlock` and 5 `FlattenedBlock` blocks have properties
  (`engraved`, `flattened`) no vanilla block has, so the carry leaves them out
  (and moves their recipes to `outside/`);
* the 154 `PathBlock`/`FacingPathBlock` blocks get vanilla stone/pumpkin
  shapes, while upstream's shape is `box(0, 0.01, 0, 16, 0.99, 16)`;
* every block needs upstream's own numbers, which it copies from the vanilla
  block named in `BlockInit` (`ofFullCopy(...)`), not from the guessed template.

This script reads the class/vanilla-copy table extracted from the upstream
`BlockInit.java` (`content/patches/upstream-blocks.json`, analysis only) and
the prepared 26.3 gameplay facts, and writes one complete declaration per
block to `content/patches/block/<name>.json`. `apply.sh` copies them over the
carry's declarations. No asset, model, blockstate, texture, recipe or loot file
is generated here: every one of those is carried from the jar.

Usage:
    python3 tools/gen_patches.py [--resources DIR] [--check]
"""
from __future__ import annotations

import argparse
import json
import os
import sys

# 26.3's MapColor ids, in the game's own order (horizon-items/src/blocks.rs).
MAP_COLORS = [
    0, 8368696, 16247203, 13092807, 16711680, 10526975, 10987431, 31744,
    16777215, 10791096, 9923917, 7368816, 4210943, 9402184, 16776437,
    14188339, 11685080, 6724056, 15066419, 8375321, 15892389, 5000268,
    10066329, 5013401, 8339378, 3361970, 6704179, 6717235, 10040115,
    1644825, 16445005, 6085589, 4882687, 55610, 8476209, 7340544, 13742497,
    10441252, 9787244, 7367818, 12223780, 6780213, 10505550, 3746083,
    8874850, 5725276, 8014168, 4996700, 4993571, 5001770, 9321518, 2430480,
    12398641, 9715553, 6035741, 1474182, 3837580, 5647422, 1356933, 6579300,
    14200723, 8365974,
]

# The shape upstream gives every PathBlock/FacingPathBlock
# (`PathBlock.SHAPE = Block.box(0, 0.01, 0, 16, 0.99, 16)`).
PATH_SHAPE = [[0.0, 0.01, 0.0, 1.0, 0.99, 1.0]]
CUBE = [[0.0, 0.0, 0.0, 1.0, 1.0, 1.0]]
ENGRAVED_SHAPE = [[0.0, 0.0, 0.0, 1.0, 15.0 / 16.0, 1.0]]

# Template per upstream class. The class decides the state space:
#   PathBlock/FacingPathBlock -> a plain cube with upstream's own shape; the
#     facing form needs a 4-value horizontal `facing` template;
#   EngravedBlock/FlattenedBlock -> a plain cube plus one declared boolean;
#   SlabBlock/StairBlock -> vanilla's slab/stair state spaces
#     (`type,waterlogged` / `facing,half,shape,waterlogged`).
TEMPLATES = {
    "PathBlock": "minecraft:stone",
    "FacingPathBlock": "minecraft:carved_pumpkin",
    "EngravedBlock": "minecraft:stone",
    "FlattenedBlock": "minecraft:stone",
    "SlabBlock": "minecraft:stone_slab",
    "StairBlock": "minecraft:stone_stairs",
}


def snake(name: str) -> str:
    """`Blocks.OAK_PLANKS` -> `oak_planks` (the constants are SCREAMING_SNAKE_CASE)."""
    return name.lower()


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    port = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--resources",
        default=os.environ.get(
            "HORIZON_RES", os.path.expanduser("~/Desktop/horizon/.local/horizon-client/26.3")
        ),
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="verify the files on disk instead of writing them",
    )
    args = ap.parse_args()

    upstream = json.load(
        open(os.path.join(port, "content/patches/upstream-blocks.json"))
    )
    facts = json.load(open(os.path.join(args.resources, "facts.json")))
    gameplay = json.load(open(os.path.join(args.resources, "gameplay-facts.json")))
    states = gameplay["states"]
    defaults = facts["defaults"]

    out_dir = os.path.join(port, "content/patches/block")
    os.makedirs(out_dir, exist_ok=True)
    failures: list[str] = []

    for name, info in sorted(upstream.items()):
        cls = info["class"]
        copy = "minecraft:" + snake(info["copy"])
        template = TEMPLATES[cls]
        state = states[defaults[copy]]
        rgb = state["map_color"]
        try:
            map_id = MAP_COLORS.index(rgb)
        except ValueError:
            failures.append(f"{name}: map colour {rgb} of {copy} is not a MapColor")
            continue
        decl: dict = {
            "template": template,
            "properties": {
                "hardness": state["hardness"],
                "explosion_resistance": state["explosion_resistance"],
                "requires_tool": state["requires_tool"],
                "friction": state["friction"],
                "map_color": map_id,
                "sounds": copy,
            },
        }
        if cls in ("PathBlock", "FacingPathBlock"):
            decl["shapes"] = {"default": PATH_SHAPE}
        elif cls == "EngravedBlock":
            decl["state_properties"] = {"engraved": {"type": "boolean"}}
            decl["shapes"] = {
                "properties": ["engraved"],
                "values": {
                    "false": CUBE,
                    "true": ENGRAVED_SHAPE,
                },
            }
        elif cls == "FlattenedBlock":
            decl["state_properties"] = {"flattened": {"type": "boolean"}}
            decl["shapes"] = {
                "properties": ["flattened"],
                "values": {
                    "false": CUBE,
                    "true": ENGRAVED_SHAPE,
                },
            }

        text = json.dumps(decl, indent=1, sort_keys=True) + "\n"
        path = os.path.join(out_dir, name + ".json")
        if args.check:
            if not os.path.exists(path):
                failures.append(f"{name}: missing {path}")
            elif open(path).read() != text:
                failures.append(f"{name}: declaration differs from generator")
        else:
            open(path, "w").write(text)

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(
        f"{'checked' if args.check else 'wrote'} {len(upstream)} block declarations: "
        f"{sum(1 for v in upstream.values() if v['class'] == 'PathBlock')} path + "
        f"{sum(1 for v in upstream.values() if v['class'] == 'FacingPathBlock')} facing + "
        f"{sum(1 for v in upstream.values() if v['class'] == 'EngravedBlock')} engraved + "
        f"{sum(1 for v in upstream.values() if v['class'] == 'FlattenedBlock')} flattened + "
        f"{sum(1 for v in upstream.values() if v['class'] == 'SlabBlock')} slab + "
        f"{sum(1 for v in upstream.values() if v['class'] == 'StairBlock')} stair"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
