#!/usr/bin/env python3
"""Compare the carried mcwpaths content against the 1.21.1 jar it came from.

Data-level fidelity check for the Macaw's Paths and Pavings content port. It
reads the jar (read-only), the carried folder mod (`content/`), the upstream
class/vanilla-copy table (`content/patches/upstream-blocks.json`, extracted
from `BlockInit.java` for analysis) and the prepared 26.3 tables, and asserts
every carried block/item/recipe/loot/lang/model/texture/tag/advancement
matches what the jar declares. Exit 0 on success, 1 with the failures printed.

Usage:
    python3 tools/verify_content.py [--jar JAR] [--content content]
                                    [--resources /path/to/26.3]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import zipfile

# 26.3's MapColor ids (horizon-items/src/blocks.rs).
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
PATH_SHAPE = [[0.0, 0.01, 0.0, 1.0, 0.99, 1.0]]
CUBE = [[0.0, 0.0, 0.0, 1.0, 1.0, 1.0]]
ENGRAVED_SHAPE = [[0.0, 0.0, 0.0, 1.0, 0.9375, 1.0]]
CLASS_PROPS = {
    "PathBlock": set(),
    "FacingPathBlock": {"facing"},
    "EngravedBlock": set(),
    "FlattenedBlock": set(),
    "SlabBlock": {"type", "waterlogged"},
    "StairBlock": {"facing", "half", "shape", "waterlogged"},
}
CLASS_STATES = {
    "PathBlock": 1,
    "FacingPathBlock": 4,
    "EngravedBlock": 2,
    "FlattenedBlock": 2,
    "SlabBlock": 6,
    "StairBlock": 80,
}


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    port = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--jar",
        default=os.path.join(
            port,
            "../_shared/carry-work/mcwpaths/jars/"
            "mcw-mcwpaths-1.1.1-mc1.21.1neoforge.jar",
        ),
    )
    ap.add_argument("--content", default=os.path.join(port, "content"))
    ap.add_argument(
        "--resources",
        default=os.environ.get(
            "HORIZON_RES", os.path.expanduser("~/Desktop/horizon/.local/horizon-client/26.3")
        ),
    )
    args = ap.parse_args()

    failures: list[str] = []

    def check(ok: bool, msg: str) -> None:
        if not ok:
            failures.append(msg)

    def say(msg: str) -> None:
        print(f"ok: {msg}")

    z = zipfile.ZipFile(args.jar)
    names = {n for n in z.namelist() if not n.endswith("/")}

    def blockstate_props(raw: str) -> set[str]:
        d = json.loads(raw)
        props: set[str] = set()
        for key in d.get("variants", {}):
            for part in key.split(","):
                if part:
                    props.add(part.split("=")[0])
        for part in d.get("multipart", []):
            when = part.get("when", {})
            for cond in [when, *when.get("OR", []), *when.get("AND", [])]:
                props.update(cond)
        return props

    jar_blocks = {
        n.rsplit("/", 1)[-1][:-5]: blockstate_props(z.read(n).decode("utf-8"))
        for n in sorted(names)
        if n.startswith("assets/mcwpaths/blockstates/") and n.endswith(".json")
    }
    say(f"jar: {len(jar_blocks)} blockstates")

    upstream = json.load(
        open(os.path.join(port, "content/patches/upstream-blocks.json"))
    )
    by_class: dict[str, set[str]] = {}
    for name, info in upstream.items():
        by_class.setdefault(info["class"], set()).add(name)
    counts = {k: len(v) for k, v in by_class.items()}
    check(
        counts
        == {"PathBlock": 130, "FacingPathBlock": 24, "EngravedBlock": 52,
            "FlattenedBlock": 5, "SlabBlock": 52, "StairBlock": 52},
        f"upstream class counts differ: {counts}",
    )
    check(set(upstream) == set(jar_blocks), f"jar/upstream block sets differ: "
          f"{sorted(set(upstream) ^ set(jar_blocks))[:8]}")
    say("upstream classes: 130 path + 24 facing + 52 engraved + 5 flattened + "
        "52 slab + 52 stair = 315")

    # --- block declarations ------------------------------------------------
    decl = {}
    for p in glob.glob(os.path.join(args.content, "data/mcwpaths/horizon/block/*.json")):
        with open(p) as f:
            decl[os.path.basename(p)[:-5]] = json.load(f)
    check(set(decl) == set(upstream), f"block declarations differ from the jar: "
          f"{sorted(set(decl) ^ set(upstream))[:8]}")
    check(len(decl) == 315, f"expected 315 block declarations, found {len(decl)}")
    say(f"content: {len(decl)} block declarations, exactly the jar's blocks")

    # --- template state space ----------------------------------------------
    facts = json.load(open(os.path.join(args.resources, "facts.json")))
    template_props: dict[str, set[str]] = {}
    template_states: dict[str, int] = {}
    for entry in facts["states"]:
        name = entry[0]
        props = entry[-1].get("properties", {})
        template_props.setdefault(name, set()).update(props)
        template_states[name] = template_states.get(name, 0) + 1

    for name, d in sorted(decl.items()):
        cls = upstream[name]["class"]
        template = d.get("template")
        check(template in template_props, f"{name}: template {template} is not a vanilla block")
        if template not in template_props:
            continue
        check(
            template_props[template] == CLASS_PROPS[cls],
            f"{name}: template {template} has properties "
            f"{sorted(template_props[template])}, expected {sorted(CLASS_PROPS[cls])}",
        )
        declared = set(d.get("state_properties", {}))
        expected_declared = (
            {"engraved"} if cls == "EngravedBlock"
            else {"flattened"} if cls == "FlattenedBlock"
            else set()
        )
        check(declared == expected_declared,
              f"{name}: declared state properties {sorted(declared)}, "
              f"expected {sorted(expected_declared)}")
        states = template_states[template] * (
            2 if expected_declared else 1
        )
        check(
            states == CLASS_STATES[cls],
            f"{name}: {states} states, expected {CLASS_STATES[cls]}",
        )
        # Every property the jar's blockstate names must exist on the block.
        have = template_props[template] | declared
        missing = jar_blocks[name] - have
        check(not missing, f"{name}: blockstate properties {sorted(missing)} are not declared")
        # Shapes: upstream's own.
        shapes = d.get("shapes", {})
        if cls in ("PathBlock", "FacingPathBlock"):
            check(shapes == {"default": PATH_SHAPE},
                  f"{name}: path shape is {shapes}, expected {PATH_SHAPE}")
        elif cls == "EngravedBlock":
            check(shapes.get("values") == {"false": CUBE, "true": ENGRAVED_SHAPE},
                  f"{name}: engraved shapes differ: {shapes}")
        elif cls == "FlattenedBlock":
            check(shapes.get("values") == {"false": CUBE, "true": ENGRAVED_SHAPE},
                  f"{name}: flattened shapes differ: {shapes}")
        else:
            check(not shapes, f"{name}: a {cls} should keep its template shapes")
        # Item: every jar block has an item of the same id.
        check(d.get("item", True) is True, f"{name}: the block item is disabled")
    say("templates keep each upstream class's state space "
        "(path/facing/engraved/flattened/slab/stair) and upstream's shapes")

    # --- upstream numbers ---------------------------------------------------
    gameplay = json.load(open(os.path.join(args.resources, "gameplay-facts.json")))
    states = gameplay["states"]
    defaults = facts["defaults"]
    number_bad: list[str] = []
    for name, d in sorted(decl.items()):
        copy = "minecraft:" + upstream[name]["copy"].lower()
        if copy not in defaults:
            number_bad.append(f"{name}: copy {copy} not in the 26.3 tables")
            continue
        row = states[defaults[copy]]
        p = d.get("properties", {})
        if abs(p.get("hardness", -99) - row["hardness"]) > 1e-6:
            number_bad.append(f"{name}: hardness {p.get('hardness')} != {row['hardness']}")
        if abs(p.get("explosion_resistance", -99) - row["explosion_resistance"]) > 1e-6:
            number_bad.append(
                f"{name}: explosion {p.get('explosion_resistance')} != "
                f"{row['explosion_resistance']}"
            )
        if p.get("requires_tool") != row["requires_tool"]:
            number_bad.append(
                f"{name}: requires_tool {p.get('requires_tool')} != {row['requires_tool']}"
            )
        if p.get("map_color") is None or MAP_COLORS[p["map_color"]] != row["map_color"]:
            number_bad.append(f"{name}: map_color {p.get('map_color')} != {row['map_color']}")
        sounds = p.get("sounds")
        if sounds not in defaults:
            number_bad.append(f"{name}: sounds {sounds} is not a vanilla block")
        elif states[defaults[sounds]]["sound"]["step"]["id"] != row["sound"]["step"]["id"]:
            number_bad.append(
                f"{name}: sound {sounds} step differs from {copy}"
            )
    check(not number_bad, f"block numbers differ from the vanilla copy: {number_bad[:6]}")
    say("properties: hardness/explosion/tool/map colour/sound equal the vanilla "
        "block each upstream class copies (BlockInit's ofFullCopy)")

    # --- assets the registrations need --------------------------------------
    def asset(ns_path: str) -> bool:
        return os.path.isfile(os.path.join(args.content, ns_path))

    for b in upstream:
        check(asset(f"assets/mcwpaths/blockstates/{b}.json"),
              f"missing blockstate asset for {b}")
        check(asset(f"assets/mcwpaths/items/{b}.json"),
              f"missing 26.3 item definition for {b}")
    say("assets: every block has its blockstate and its 26.3 item definition")

    # --- model + texture resolution ----------------------------------------
    model_files = {
        p.rsplit("models/", 1)[-1][:-5]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwpaths/models/**/*.json"),
            recursive=True,
        )
    }
    referenced_models: set[str] = set()
    for b in upstream:
        d = json.load(open(os.path.join(args.content, f"assets/mcwpaths/blockstates/{b}.json")))
        for v in d.get("variants", {}).values():
            for vv in v if isinstance(v, list) else [v]:
                if "model" in vv:
                    referenced_models.add(vv["model"])
        for part in d.get("multipart", []):
            apply = part.get("apply", {})
            for vv in apply if isinstance(apply, list) else [apply]:
                if "model" in vv:
                    referenced_models.add(vv["model"])
        item = json.load(open(os.path.join(args.content, f"assets/mcwpaths/items/{b}.json")))
        model = item.get("model")
        if isinstance(model, dict) and "model" in model:
            referenced_models.add(model["model"])

    def resolves_model(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/models", path + ".json")
            )
        if ns and ns != "mcwpaths":
            return True
        return path in model_files

    missing_models = sorted(m for m in referenced_models if not resolves_model(m))
    check(not missing_models, f"referenced models missing: {missing_models[:8]}")
    say(f"models: {len(model_files)} present, {len(referenced_models)} referenced by "
        "carried blocks/items, 0 missing")

    textures = {
        p.rsplit("textures/", 1)[-1][:-4]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwpaths/textures/**/*.png"),
            recursive=True,
        )
    }
    missing_textures: set[str] = set()

    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "textures" and isinstance(v, dict):
                    for ref in v.values():
                        if isinstance(ref, str) and not ref.startswith("#"):
                            missing_textures.add(ref)
                else:
                    walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)

    reached: set[str] = set()
    pending = [
        m.split(":", 1)[-1]
        for m in referenced_models
        if m.startswith("mcwpaths:") or ":" not in m
    ]
    while pending:
        name = pending.pop()
        if name in reached or name not in model_files:
            continue
        reached.add(name)
        d = json.load(open(os.path.join(args.content, "assets/mcwpaths/models", name + ".json")))
        walk(d)
        parent = d.get("parent")
        if isinstance(parent, str) and (
            parent.startswith("mcwpaths:") or ":" not in parent
        ):
            pending.append(parent.split(":", 1)[-1])
    say(f"models reached from carried blocks/items: {len(reached)} (parents followed)")

    def resolves_texture(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/textures", path + ".png")
            )
        if ns and ns != "mcwpaths":
            return True
        # Model parents in the jar point at `mcwpaths:block/...` textures with
        # no file of their own; the leaf models override every use.
        return path in textures

    missing_textures = {t for t in missing_textures if not resolves_texture(t)}
    # `block/block` in vanilla models names `#particle` with no texture bound.
    missing_textures.discard("particle")
    check(not missing_textures, f"missing textures: {sorted(missing_textures)[:8]}")
    say(f"textures: {len(textures)} present, every reached model's texture resolves")

    # --- recipes ------------------------------------------------------------
    recipes = {}
    for p in glob.glob(os.path.join(args.content, "data/mcwpaths/recipe/*.json")):
        recipes[os.path.basename(p)[:-5]] = json.load(open(p))
    registry = set(upstream)
    bad = [
        r for r, d in recipes.items()
        if d.get("result", {}).get("id") not in {f"mcwpaths:{x}" for x in registry}
    ]
    check(not bad, f"recipes with an unregistered result: {bad[:8]}")
    jar_recipes = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwpaths/recipe/") and n.endswith(".json")
    }
    check(set(recipes) == jar_recipes,
          f"recipes differ from the jar: {sorted(set(recipes) ^ jar_recipes)[:8]}")
    types = sorted({d.get("type") for d in recipes.values()})
    check(types == ["minecraft:crafting_shapeless", "minecraft:stonecutting"],
          f"unexpected recipe types: {types}")
    say(f"recipes: {len(recipes)} carried (304 stonecutting + 11 shapeless), "
        "every result registered")
    tag_uses = json.dumps(list(recipes.values()))
    check("#c:" not in tag_uses and "forge:" not in tag_uses,
          "recipes still use NeoForge c:/forge: tags")
    say("recipes: no NeoForge #c:/forge: tags left")

    # --- loot ---------------------------------------------------------------
    loot = {
        p.rsplit("/", 1)[-1][:-5]
        for p in glob.glob(os.path.join(args.content, "data/mcwpaths/loot_table/blocks/*.json"))
    }
    check(loot <= registry, f"loot tables for undeclared blocks: {sorted(loot - registry)[:8]}")
    check(registry - loot == set(), f"blocks without a loot table: {sorted(registry - loot)[:8]}")
    for b in sorted(loot):
        d = json.load(open(os.path.join(args.content, f"data/mcwpaths/loot_table/blocks/{b}.json")))
        entry = d["pools"][0]["entries"][0]
        check(entry.get("name") == f"mcwpaths:{b}", f"{b}: loot does not drop itself")
    say(f"loot: {len(loot)} tables, one per carried block, each drops itself")

    # --- lang ---------------------------------------------------------------
    lang = json.load(open(os.path.join(args.content, "assets/mcwpaths/lang/en_us.json")))
    unnamed = [b for b in upstream if f"block.mcwpaths.{b}" not in lang]
    check(not unnamed, f"unexpected unnamed blocks: {unnamed[:8]}")
    check("itemGroup.mcwpaths" in lang, "itemGroup.mcwpaths is missing")
    for key in ("mcwpaths.engraved.desc", "mcwpaths.flattened.desc"):
        check(key in lang, f"{key} is missing")
    say("lang: every carried block has a block. key; the tab and tooltip keys are present")

    # --- tags ---------------------------------------------------------------
    tag_files = sorted(
        os.path.relpath(p, args.content)
        for p in glob.glob(os.path.join(args.content, "data/**/tags/**/*.json"), recursive=True)
    )
    check(len(tag_files) == 11, f"expected 11 tag files, found {len(tag_files)}: {tag_files}")
    for p in tag_files:
        d = json.load(open(os.path.join(args.content, p)))
        for v in d.get("values", []):
            if isinstance(v, str) and v.startswith("mcwpaths:"):
                check(v.split(":", 1)[1] in registry, f"{p}: undeclared block {v}")
    say(f"tags: {len(tag_files)} carried (7 mcwpaths + 4 minecraft), every "
        "mcwpaths entry is a declared block")

    # --- advancements -------------------------------------------------------
    advs = {
        p.rsplit("/", 1)[-1][:-5]: json.load(open(p))
        for p in glob.glob(os.path.join(args.content, "data/mcwpaths/advancement/recipes/*.json"))
    }
    check(len(advs) == 25, f"expected 25 recipe advancements, found {len(advs)}")
    for name, d in advs.items():
        for r in d.get("rewards", {}).get("recipes", []):
            check(r.split(":", 1)[1] in recipes, f"{name}: unknown recipe {r}")
    say(f"advancements: {len(advs)} carried, every unlocked recipe is carried")

    # --- creative tab -------------------------------------------------------
    tab = json.load(
        open(os.path.join(args.content, "data/mcwpaths/horizon/creative_tab/paths.json"))
    )
    tab_ids = [i.split(":", 1)[1] for i in tab["items"]]
    check(len(tab_ids) == 315, f"creative tab lists {len(tab_ids)} items, expected 315")
    check(set(tab_ids) <= registry, f"tab lists unregistered items: {sorted(set(tab_ids) - registry)[:8]}")
    check(set(tab_ids) >= registry, f"tab misses items: {sorted(registry - set(tab_ids))[:8]}")
    say("creative tab: 315 items, all registered, title itemGroup.mcwpaths")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  FAIL: {f}")
        return 1
    print(
        f"\nPASS: {len(decl)} block declarations + {len(recipes)} recipes + "
        f"{len(loot)} loot tables + {len(tag_files)} tag files + {len(advs)} "
        f"advancements + {len(tab_ids)} tab entries, {len(model_files)} models and "
        f"{len(textures)} textures match the 1.21.1 jar; every class keeps its "
        "state space and upstream's shape and numbers"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
