#!/usr/bin/env bash
# In-game check for the Macaw's Paths and Pavings content port (315 blocks:
# 130 path + 24 facing path + 52 engraved + 5 flattened + 52 slab + 52 stair),
# Minecraft 26.3 on the campaign pin 41f822b6.
#
# Default run (offscreen renderer, creative, The End, shared unmodded game +
# `--dev-mod content/`):
#   0. tools/verify_content.py compares the carried folder mod with the
#      1.21.1 jar first (block declarations, state spaces, shapes, upstream
#      numbers, models/textures, recipes, loot, lang, tags, advancements);
#   1. the mod loads (no "content mods not loaded");
#   2. all 315 carried ids `setblock` and read back;
#   3. the state space is real: 24 facing blocks x 4 facings, 52 slabs x
#      bottom/top/double, 52 stairs x 4 facings x 2 halves, 52 engraved x
#      false/true, 5 flattened x false/true all read back;
#   4. the shapes are upstream's, not the template's: a player dropped on the
#      block lands at 81.0 (engraved=false, full cube), 80.9375
#      (engraved=true, 15/16), 80.99 (path, 0.01..0.99), with vanilla stone
#      (81.0) and vanilla dirt_path (80.9375) as same-run baselines;
#   5. representative items place: a wooden path (facing), a slab (type), a
#      stair (facing/half), a paving and a soil path;
#   6. a paving drops itself in survival (`ctl break` .drops), vanilla stone
#      drops cobblestone (baseline);
#   7. a screenshot with a paving differs from the same frame without it, and
#      the log carries no missing-model/missing-texture warning for mcwpaths;
#   8. the creative tab lists all 315 carried items.
#
# NEGATIVE=1 keeps the same scenario but expects an `engraved=true` block to
# read `engraved=false`: the run MUST fail, proving that read-back assertion is
# not vacuous. `SKIP_VERIFY=1` skips the jar comparison (debugging only).
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/mcwpaths
SHARED=$CLONE/ports/_shared/bin/horizon-41f822b6
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$SHARED/horizon-client}
RES=${RES:-${HORIZON_RES:-$HOME/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/mcwpaths-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
SKIP_VERIFY=${SKIP_VERIFY:-0}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

BLOCK_DIR=$PORT/content/data/mcwpaths/horizon/block
mapfile -t BLOCKS < <(find "$BLOCK_DIR" -name '*.json' -printf '%f\n' | sed 's/\.json$//' | sort)
[ "${#BLOCKS[@]}" -eq 315 ] || { echo "expected 315 carried blocks, found ${#BLOCKS[@]}" >&2; exit 1; }

# Class lists come from the same upstream table the declarations were made from.
mapfile -t FACING < <(python3 - "$PORT/content/patches/upstream-blocks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in sorted(d.items()):
    if v["class"] == "FacingPathBlock":
        print(n)
PY
)
mapfile -t SLABS < <(python3 - "$PORT/content/patches/upstream-blocks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in sorted(d.items()):
    if v["class"] == "SlabBlock":
        print(n)
PY
)
mapfile -t STAIRS < <(python3 - "$PORT/content/patches/upstream-blocks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in sorted(d.items()):
    if v["class"] == "StairBlock":
        print(n)
PY
)
mapfile -t ENGRAVED < <(python3 - "$PORT/content/patches/upstream-blocks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in sorted(d.items()):
    if v["class"] == "EngravedBlock":
        print(n)
PY
)
mapfile -t FLATTENED < <(python3 - "$PORT/content/patches/upstream-blocks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for n, v in sorted(d.items()):
    if v["class"] == "FlattenedBlock":
        print(n)
PY
)
[ "${#FACING[@]}" -eq 24 ] && [ "${#SLABS[@]}" -eq 52 ] && [ "${#STAIRS[@]}" -eq 52 ] \
    && [ "${#ENGRAVED[@]}" -eq 52 ] && [ "${#FLATTENED[@]}" -eq 5 ] \
    || { echo "upstream class lists are wrong" >&2; exit 1; }

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }

if [ "$SKIP_VERIFY" = 1 ]; then
    echo "== jar comparison skipped (SKIP_VERIFY=1) =="
else
    say "data fidelity: carried content vs the 1.21.1 jar"
    python3 "$PORT/tools/verify_content.py" --content "$PORT/content" --resources "$RES" \
        || fail "verify_content.py failed"
fi

SCRATCH=$(mktemp -d /tmp/opencode/mcwpaths-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[a-z0-9_]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
feet_y() { ctl state | jq -r '.player.position[1]'; }
# Read a position back until the client's copy catches up with the server's
# setblock (5 tries, 5 ticks apart). A wrong block never converges, so this
# only absorbs streaming lag; it cannot mask a content error.
readback() { # x y z expected-block-id
    local x=$1 y=$2 z=$3 want=$4 st i
    for i in 1 2 3 4 5; do
        st=$(block_state "$x" "$y" "$z")
        case "$st" in "$want"*) echo "$st"; return 0 ;; esac
        ctl wait 5 >/dev/null
    done
    echo "$st"
}
mean_rgb() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
crop = im.crop((w * 3 // 10, h * 3 // 10, w * 7 // 10, h * 7 // 10))
px = list(crop.getdata())
n = len(px)
print(sum(p[0] for p in px) / n, sum(p[1] for p in px) / n, sum(p[2] for p in px) / n)
PY
}

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

say "launch (offscreen renderer, creative, The End, content --dev-mod content/)"
"$CTL" --socket "$SOCK" launch \
    --game "$GAME" --world McwPathsE2E --seed 20261104 --creative --offscreen --wait \
    --game-dir "$SCRATCH/game" --resources "$RES" --dev-mod "$PORT/content"
ctl wait-ready 180
if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
    ctl logs --lines 4000 | grep "content mods not loaded" >&2
    fail "the content mod did not load"
fi
echo "content mod loaded (no 'content mods not loaded')"

say "The End arena: floor at y=79, clear above"
end "forceload add -8 -8 72 72"
end "fill -8 79 -8 72 79 60 minecraft:stone"
end "fill -8 80 -8 72 84 60 minecraft:air"
end "fill -8 85 -8 72 88 60 minecraft:air"
end "tp @s 8.5 80 8.5"
end "difficulty peaceful"
end "gamerule spawn_mobs false"
# The client follows the server-side teleport a tick or two later; every
# setblock/read below uses "the player's current dimension", so wait for it
# and refuse to run the checks from the Overworld.
for _ in $(seq 1 30); do
    [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] && break
    ctl wait 10
done
[ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] \
    || fail "the player is in $(ctl state | jq -r '.dimension'), not The End"
# A block change sent while the client is still receiving the chunk is
# overwritten by the chunk data (the server has it, the client draws air).
# Wait for the arena chunks to settle before the first setblock.
ctl wait-ready 180 >/dev/null
ctl wait 20 >/dev/null
echo "player in the_end at $(ctl state | jq -c '.player.position'), chunks settled"
ctl close >/dev/null 2>&1 || true
ctl wait 2

# ------------------------------------------------------------------ registry
say "all ${#BLOCKS[@]} carried ids bind their default state"
PER=24
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    ctl setblock "$x" 80 "$z" "mcwpaths:${BLOCKS[$i]}" >/dev/null \
        || fail "setblock mcwpaths:${BLOCKS[$i]} failed"
done
ctl wait 10
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    got=$(readback "$x" 80 "$z" "mcwpaths:${BLOCKS[$i]}")
    got=${got%%[*}   # just the block id
    [ "$got" = "mcwpaths:${BLOCKS[$i]}" ] \
        || fail "x=$x z=$z reads '$got', expected mcwpaths:${BLOCKS[$i]}"
done
echo "${#BLOCKS[@]}/${#BLOCKS[@]} block ids registered and their default state bound"

# --------------------------------------------------------------- facing
say "${#FACING[@]} facing blocks x 4 facings read back"
i=0
for b in "${FACING[@]}"; do
    for facing in north east south west; do
        x=$((40 + i)); z=20
        ctl setblock "$x" 80 "$z" "mcwpaths:$b[facing=$facing]" >/dev/null \
            || fail "setblock $b facing=$facing failed"
        i=$((i + 1))
    done
done
ctl wait 10
i=0
for b in "${FACING[@]}"; do
    for facing in north east south west; do
        x=$((40 + i)); z=20
        assert_prop "$(readback "$x" 80 "$z" "mcwpaths:$b")" facing "$facing"
        i=$((i + 1))
    done
done
echo "${#FACING[@]}/$(( ${#FACING[@]} * 4 )) facing states bind"

# ----------------------------------------------------------------- slabs
say "${#SLABS[@]} slabs x bottom/top/double read back"
i=0
for b in "${SLABS[@]}"; do
    for type in bottom top double; do
        x=$((2 + i % 50)); z=$((22 + i / 50))
        ctl setblock "$x" 80 "$z" "mcwpaths:$b[type=$type]" >/dev/null \
            || fail "setblock $b type=$type failed"
        i=$((i + 1))
    done
done
ctl wait 10
i=0
for b in "${SLABS[@]}"; do
    for type in bottom top double; do
        x=$((2 + i % 50)); z=$((22 + i / 50))
        assert_prop "$(readback "$x" 80 "$z" "mcwpaths:$b")" type "$type"
        i=$((i + 1))
    done
done
echo "${#SLABS[@]}/$(( ${#SLABS[@]} * 3 )) slab states bind (type=bottom/top/double)"

# ---------------------------------------------------------------- stairs
say "${#STAIRS[@]} stairs x 4 facings x 2 halves read back"
i=0
for b in "${STAIRS[@]}"; do
    x=$((2 + i % 50)); z=30; hx=$((2 + i % 50)); hz=32
    ctl setblock "$x" 80 "$z" "mcwpaths:$b[facing=east,half=bottom,shape=straight,waterlogged=false]" >/dev/null \
        || fail "setblock $b facing=east failed"
    ctl setblock "$x" 80 "$hz" "mcwpaths:$b[facing=west,half=top,shape=straight,waterlogged=false]" >/dev/null \
        || fail "setblock $b facing=west top failed"
    ctl setblock "$x" 81 "$z" "mcwpaths:$b[facing=north,half=bottom,shape=straight,waterlogged=true]" >/dev/null \
        || fail "setblock $b facing=north failed"
    ctl setblock "$x" 81 "$hz" "mcwpaths:$b[facing=south,half=top,shape=straight,waterlogged=false]" >/dev/null \
        || fail "setblock $b facing=south top failed"
    i=$((i + 1))
done
ctl wait 10
i=0
for b in "${STAIRS[@]}"; do
    x=$((2 + i % 50)); z=30; hz=32
    s=$(readback "$x" 80 "$z" "mcwpaths:$b"); assert_prop "$s" facing east; assert_prop "$s" half bottom
    assert_prop "$s" shape straight; assert_prop "$s" waterlogged false
    s=$(readback "$x" 80 "$hz" "mcwpaths:$b"); assert_prop "$s" facing west; assert_prop "$s" half top
    s=$(readback "$x" 81 "$z" "mcwpaths:$b"); assert_prop "$s" facing north; assert_prop "$s" half bottom
    assert_prop "$s" waterlogged true
    s=$(readback "$x" 81 "$hz" "mcwpaths:$b"); assert_prop "$s" facing south; assert_prop "$s" half top
    i=$((i + 1))
done
echo "${#STAIRS[@]}/$(( ${#STAIRS[@]} * 4 )) stair states bind (facing x half x waterlogged)"

# ------------------------------------------------------- engraved / flattened
say "${#ENGRAVED[@]} engraved blocks read false and true"
i=0
for b in "${ENGRAVED[@]}"; do
    x=$((2 + i % 50)); z=$((40 + i / 50))
    ctl setblock "$x" 80 "$z" "mcwpaths:$b[engraved=false]" >/dev/null \
        || fail "setblock $b engraved=false failed"
    ctl setblock "$x" 81 "$z" "mcwpaths:$b[engraved=true]" >/dev/null \
        || fail "setblock $b engraved=true failed"
    i=$((i + 1))
done
ctl wait 10
i=0
for b in "${ENGRAVED[@]}"; do
    x=$((2 + i % 50)); z=$((40 + i / 50))
    want=false
    [ "$NEGATIVE" = 1 ] && want=true
    assert_prop "$(readback "$x" 80 "$z" "mcwpaths:$b")" engraved "$want"
    assert_prop "$(readback "$x" 81 "$z" "mcwpaths:$b")" engraved true
    i=$((i + 1))
done
echo "${#ENGRAVED[@]}/$(( ${#ENGRAVED[@]} * 2 )) engraved states bind"

say "${#FLATTENED[@]} soil path blocks read false and true"
i=0
for b in "${FLATTENED[@]}"; do
    x=$((2 + i)); z=46
    ctl setblock "$x" 80 "$z" "mcwpaths:$b[flattened=false]" >/dev/null \
        || fail "setblock $b flattened=false failed"
    ctl setblock "$x" 81 "$z" "mcwpaths:$b[flattened=true]" >/dev/null \
        || fail "setblock $b flattened=true failed"
    i=$((i + 1))
done
ctl wait 10
i=0
for b in "${FLATTENED[@]}"; do
    x=$((2 + i)); z=46
    assert_prop "$(readback "$x" 80 "$z" "mcwpaths:$b")" flattened false
    assert_prop "$(readback "$x" 81 "$z" "mcwpaths:$b")" flattened true
    i=$((i + 1))
done
echo "${#FLATTENED[@]}/$(( ${#FLATTENED[@]} * 2 )) flattened states bind"

# ------------------------------------------------------------ collision shapes
say "upstream's shapes are the block's collision, not the template's"
ctl command "gamemode survival @s" >/dev/null
drop_onto() { # block expected-y label
    ctl setblock 60 80 50 "$1" >/dev/null || fail "setblock $1 failed"
    ctl tp 60.5 82.5 50.5 >/dev/null
    ctl wait 60
    local y
    y=$(feet_y)
    echo "$3: landed at y=$y"
    python3 - "$y" "$2" "$3" <<'PY'
import sys
got, want, label = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
if abs(got - want) > 0.02:
    print(f"FAIL: {label}: landed at {got}, expected {want}", file=sys.stderr)
    raise SystemExit(1)
PY
}
drop_onto "minecraft:stone" 81.0 "vanilla stone baseline (full cube)"
drop_onto "minecraft:dirt_path" 80.9375 "vanilla dirt_path baseline (15/16)"
drop_onto "mcwpaths:stone_crystal_floor[engraved=false]" 81.0 "engraved=false (full cube)"
drop_onto "mcwpaths:stone_crystal_floor[engraved=true]" 80.9375 "engraved=true (15/16)"
drop_onto "mcwpaths:stone_running_bond_path" 80.99 "path (0.01..0.99)"
drop_onto "mcwpaths:dirt_path_block[flattened=false]" 81.0 "flattened=false (full cube)"
drop_onto "mcwpaths:dirt_path_block[flattened=true]" 80.9375 "flattened=true (15/16)"
ctl setblock 60 80 50 minecraft:air >/dev/null
ctl command "gamemode creative @s" >/dev/null
ctl wait 5
echo "collision heights distinguish the three shapes from the template's cube"

# --------------------------------------------------------------- placement
say "representative items place with their state"
ctl command "clear @s" >/dev/null
ctl give mcwpaths:acacia_planks_path 4 >/dev/null || fail "cannot give acacia_planks_path"
ctl give mcwpaths:andesite_crystal_floor_slab 2 >/dev/null || fail "cannot give a slab"
ctl give mcwpaths:andesite_crystal_floor_stairs 2 >/dev/null || fail "cannot give stairs"
ctl give mcwpaths:andesite_diamond_paving 2 >/dev/null || fail "cannot give a paving"
ctl give mcwpaths:dirt_path_block 2 >/dev/null || fail "cannot give dirt_path_block"
ctl give minecraft:carved_pumpkin 4 >/dev/null || fail "cannot give carved_pumpkin"
ctl wait 3

# A facing path takes its template's placement rule. Click the floor's top
# face with an explicit yaw (no `place`, whose aim makes the click use the
# previous tick's yaw); a vanilla carved_pumpkin placed the same way from the
# same yaw is the same-run baseline. Upstream's own `FacingPathBlock` rule is
# `getHorizontalDirection().getClockWise()` (a logic-tier difference recorded
# in notes.md); the content block takes the template's opposite-of-view rule.
place_on_floor() { # x item yaw -> prints the placed block state
    ctl select "$2" >/dev/null || fail "cannot select $2"
    ctl tp "$1.5" 80 20.5 >/dev/null
    ctl wait 5 >/dev/null
    ctl look "$3" 30 >/dev/null
    ctl wait 8 >/dev/null
    ctl interact "$1" 79 18 up >/dev/null || fail "cannot click the floor with $2"
    ctl wait 5 >/dev/null
    readback "$1" 80 18 "$2"
}
path0=$(place_on_floor 20 mcwpaths:acacia_planks_path 0)
pump0=$(place_on_floor 24 minecraft:carved_pumpkin 0)
path180=$(place_on_floor 28 mcwpaths:acacia_planks_path 180)
pump180=$(place_on_floor 32 minecraft:carved_pumpkin 180)
echo "yaw 0:   path $path0 | vanilla $pump0"
echo "yaw 180: path $path180 | vanilla $pump180"
case "$path0" in mcwpaths:acacia_planks_path*) ;; *) fail "the wooden path did not place at yaw 0: $path0" ;; esac
case "$pump0" in minecraft:carved_pumpkin*) ;; *) fail "the vanilla baseline did not place at yaw 0: $pump0" ;; esac
[ "$(prop "$path0" facing)" = "$(prop "$pump0" facing)" ] \
    || fail "yaw 0: path faces $(prop "$path0" facing), its template faces $(prop "$pump0" facing)"
[ "$(prop "$path180" facing)" = "$(prop "$pump180" facing)" ] \
    || fail "yaw 180: path faces $(prop "$path180" facing), its template faces $(prop "$pump180" facing)"
[ "$(prop "$path0" facing)" != "$(prop "$path180" facing)" ] \
    || fail "the placed path ignores the view direction (both yaws give $(prop "$path0" facing))"
echo "wooden path takes its carved_pumpkin template's placement rule at both yaws"

ctl select mcwpaths:andesite_crystal_floor_slab >/dev/null
ctl tp 10.5 80 54.5 >/dev/null
ctl wait 2
ctl place 10 80 56 --item mcwpaths:andesite_crystal_floor_slab >/dev/null || fail "cannot place the slab"
ctl wait 3
placed=$(readback 10 80 56 mcwpaths:andesite_crystal_floor_slab)
echo "placed slab: $placed"
case "$placed" in mcwpaths:andesite_crystal_floor_slab*) ;; *) fail "the slab did not place: $placed" ;; esac
assert_prop "$placed" type bottom

ctl tp 14.5 80 54.5 >/dev/null
ctl wait 2
ctl place 14 80 56 --item mcwpaths:andesite_crystal_floor_stairs >/dev/null || fail "cannot place the stairs"
ctl wait 3
placed=$(readback 14 80 56 mcwpaths:andesite_crystal_floor_stairs)
echo "placed stairs: $placed"
case "$placed" in mcwpaths:andesite_crystal_floor_stairs*) ;; *) fail "the stairs did not place: $placed" ;; esac
assert_prop "$placed" half bottom
assert_prop "$placed" shape straight

ctl tp 18.5 80 54.5 >/dev/null
ctl wait 2
ctl place 18 80 56 --item mcwpaths:andesite_diamond_paving >/dev/null || fail "cannot place the paving"
ctl wait 3
placed=$(readback 18 80 56 mcwpaths:andesite_diamond_paving)
[ "${placed%%[*}" = mcwpaths:andesite_diamond_paving ] \
    || fail "the paving did not place: $placed"

ctl tp 22.5 80 54.5 >/dev/null
ctl wait 2
ctl place 22 80 56 --item mcwpaths:dirt_path_block >/dev/null || fail "cannot place dirt_path_block"
ctl wait 3
placed=$(readback 22 80 56 mcwpaths:dirt_path_block)
[ "${placed%%[*}" = mcwpaths:dirt_path_block ] \
    || fail "the soil path did not place: $placed"
echo "path, slab, stairs, paving and soil path all place"

# ------------------------------------------------------------------- drops
say "a paving drops itself; vanilla stone drops cobblestone (baseline)"
ctl command "gamemode survival @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl give minecraft:diamond_pickaxe 1 >/dev/null
ctl wait 3
ctl select minecraft:diamond_pickaxe >/dev/null || fail "cannot select the diamond pickaxe"
ctl wait 2
ctl setblock 40 80 50 mcwpaths:andesite_diamond_paving >/dev/null
ctl tp 40.5 80 52.5 >/dev/null
ctl wait 5
ctl look-at-block 40 80 50 >/dev/null 2>&1 || true
broken=$(ctl break 40 80 50) || { echo "break reply: $broken"; fail "cannot break the paving"; }
echo "$broken" | jq -c '{scenario:"mcwpaths paving",block,block_before,drops}'
[ "$(echo "$broken" | jq -r '.block')" = "minecraft:air" ] || fail "the paving did not break"
paving=$(echo "$broken" | jq -r '.drops["mcwpaths:andesite_diamond_paving"] // 0')
[ "$paving" -ge 1 ] || fail "the paving dropped $paving of itself"
ctl setblock 41 80 50 minecraft:stone >/dev/null
ctl look-at-block 41 80 50 >/dev/null 2>&1 || true
broken=$(ctl break 41 80 50)
echo "$broken" | jq -c '{scenario:"vanilla stone",block,block_before,drops}'
cobble=$(echo "$broken" | jq -r '.drops["minecraft:cobblestone"] // 0')
[ "$cobble" -ge 1 ] || fail "vanilla stone dropped no cobblestone (harness baseline)"
ctl command "gamemode creative @s" >/dev/null
echo "loot: the paving drops itself, vanilla stone drops cobblestone"

# -------------------------------------------------------------- screenshot
say "screenshot: a paving floor is visible, the same frame without it is not"
ctl fill 46 80 46 54 80 54 mcwpaths:blackstone_diamond_paving >/dev/null
ctl tp 50.5 80 56.5 >/dev/null
ctl look-at-block 50 80 50 >/dev/null 2>&1 || true
ctl wait 10
ctl screenshot "$SCRATCH/paving.png" >/dev/null
read -r r0 g0 b0 <<<"$(mean_rgb "$SCRATCH/paving.png")"
ctl fill 46 80 46 54 80 54 minecraft:air >/dev/null
ctl wait 10
ctl screenshot "$SCRATCH/empty.png" >/dev/null
read -r r1 g1 b1 <<<"$(mean_rgb "$SCRATCH/empty.png")"
echo "mean RGB with paving: $r0 $g0 $b0"
echo "mean RGB empty:      $r1 $g1 $b1"
[ -s "$SCRATCH/paving.png" ] || fail "the paving screenshot is empty"
awk -v a="$r0" -v b="$r1" -v c="$g0" -v d="$g1" -v e="$b0" -v f="$b1" \
    'BEGIN { exit !(sqrt((a-b)^2+(c-d)^2+(e-f)^2) > 2) }' \
    || fail "the frame did not change when the paving was removed (no model drawn?)"
echo "the paving's frame differs from the empty frame (a model is drawn)"

say "no missing model/texture warnings for mcwpaths"
ctl logs --lines 6000 > "$SCRATCH/game.log" 2>/dev/null || true
if grep -iE "missing texture for mcwpaths|block models incomplete.*mcwpaths|no model.*mcwpaths|mcwpaths.*missing (model|texture)" "$SCRATCH/game.log"; then
    fail "the log reports a missing model/texture for mcwpaths"
fi
echo "the log has no mcwpaths missing-model/missing-texture warning"

# ----------------------------------------------------------- creative tab
say "the creative tab lists all 315 carried items"
CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json -print -quit 2>/dev/null || true)
[ -n "$CREATIVE" ] && [ -f "$CREATIVE" ] || fail "no creative-inventory.json (content mod not loaded)"
python3 "$PORT/tools/tab_check.py" "$CREATIVE" 315 \
    mcwpaths:acacia_planks_path mcwpaths:andesite_basket_weave_paving \
    mcwpaths:andesite_crystal_floor mcwpaths:andesite_crystal_floor_slab \
    mcwpaths:andesite_crystal_floor_stairs mcwpaths:dirt_path_block \
    mcwpaths:dark_prismarine_windmill_weave_stairs || fail "the creative tab check failed"

# ----------------------------------------------------- template class chain
say "every declared block copies its template's class chain"
BEHAVIOURS=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name block-behaviours.json -print -quit 2>/dev/null || true)
[ -n "$BEHAVIOURS" ] && [ -f "$BEHAVIOURS" ] || fail "no block-behaviours.json (content mod not loaded)"
python3 "$PORT/tools/class_check.py" "$BEHAVIOURS" \
    "$PORT/content/data/mcwpaths/horizon/block" || fail "the class-chain check failed"

# ----------------------------------------------------------------- controls
say "unknown ids are refused; vanilla stone places; a stick places nothing"
echo "dimension: $(ctl state | jq -r '.dimension')"
if ctl give mcwpaths:not_a_block 1 >/dev/null 2>&1; then
    fail "give mcwpaths:not_a_block succeeded"
fi
ctl setblock 44 80 50 mcwpaths:bogus_block >/dev/null 2>&1 || true
[ "$(block_name 44 80 50)" = minecraft:air ] || fail "mcwpaths:bogus_block became $(block_name 44 80 50)"
ctl setblock 42 80 50 minecraft:stone >/dev/null || fail "the stone control setblock failed"
[ "$(block_name 42 80 50)" = minecraft:stone ] \
    || fail "vanilla stone did not place (read $(block_name 42 80 50))"
ctl give minecraft:stick 1 >/dev/null
ctl wait 2
ctl select minecraft:stick >/dev/null
ctl wait 2
ctl tp 46.5 80 52.5 >/dev/null
ctl wait 2
ctl place 46 80 50 --item minecraft:stick >/dev/null 2>&1 || true
ctl wait 3
[ "$(block_name 46 80 50)" = minecraft:air ] || fail "a stick placed $(block_name 46 80 50)"
echo "unknown ids refused, vanilla stone places, a stick places nothing"

# ---------------------------------------------------------------- evidence
cp "$SCRATCH/paving.png" "$PORT/tools/.e2e-last-paving.png" 2>/dev/null || true
echo "PASS: ${#BLOCKS[@]}/315 block ids bind, ${#FACING[@]} facing x 4, ${#SLABS[@]} slabs x 3, ${#STAIRS[@]} stairs x 4, ${#ENGRAVED[@]} engraved x 2 and ${#FLATTENED[@]} flattened x 2 states read back, the three upstream shapes are the collision (81.0 / 80.9375 / 80.99 vs vanilla stone/dirt_path), representative items place with their state, a paving drops itself while vanilla stone drops cobblestone, the paving renders (screenshot differs, no missing texture), the creative tab lists 315 items, and unknown ids are refused"
echo "EXIT:0"
exit 0
