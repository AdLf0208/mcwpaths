#!/usr/bin/env bash
# Re-apply the hand patches after a fresh `horizon-port-pack carry` (it deletes
# and rewrites carry/). Run from ports/mcwpaths/content.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=$(cd .. && pwd)
OUTSIDE=${OUTSIDE:-$PORT/../_shared/carry-work/mcwpaths/mods/mcwpaths/outside}

# 1. The 26.3 block declarations. The raw carry (no NeoForge oracle) only has
#    a template guess: it leaves the 52 EngravedBlock + 5 FlattenedBlock blocks
#    out (no vanilla block has `engraved`/`flattened`), and its stone/pumpkin
#    shapes are not upstream's 0.01..0.99 path shape. tools/gen_patches.py
#    writes one complete declaration per block from the upstream class/copy
#    table and the prepared 26.3 numbers.
python3 ../tools/gen_patches.py
cp patches/block/*.json data/mcwpaths/horizon/block/

# 2. The Java creative tab (`TabInit`) is code; mirror it as 26.3 data. The
#    order is upstream's, filtered to the blocks this 1.1.1 jar has (the repo's
#    newer `pale_oak_planks_path` is not in the jar).
mkdir -p data/mcwpaths/horizon/creative_tab
cp patches/tab/paths.json data/mcwpaths/horizon/creative_tab/paths.json

# 3. The carry moves a recipe to `outside/` when its result is a block it left
#    out. Those 57 blocks are declared by patch 1, so their recipes come back
#    (the carry already upgraded them to 26.3; nothing is rewritten here).
restored=0
for f in "$OUTSIDE"/data/mcwpaths/recipe/*.json; do
    [ -e "$f" ] || continue
    cp "$f" data/mcwpaths/recipe/
    restored=$((restored + 1))
done
[ "$restored" -eq 57 ] || {
    echo "expected 57 restored recipes, restored $restored (outside: $OUTSIDE)" >&2
    exit 1
}
echo "patches applied: 315 block declarations, 1 creative tab, 57 restored recipes"
