# Macaw's Paths and Pavings — Horizon port

A port of [Macaw's Paths and Pavings](https://github.com/sketchmacaw/Paths-Pavings) by Sketch Macaw and Peachy Macaw for
Horizon. A data-tier carry with hand-written 26.3 block declarations: no native code and no hooks.

**Status:** the slice below is what works today; the second list is what is
missing. Nothing here claims parity with the original.

## What works

- All 315 blocks: 130 thin path/paving blocks, 24 facing paths, 52 engraved pavings, 5
  flattened soil paths, 52 slabs and 52 stairs — 4,812 block states, each with the mod's
  own model and texture.
- The thin paving shape (0.01–0.99) and the engraved/flattened 15/16 shape are declared,
  not inherited from the template, so the collision matches upstream.
- 315 recipes (304 stonecutting, 11 shapeless), 315 loot tables, 11 tags, 25
  advancements and 7 language files.
- A creative tab (`itemGroup.mcwpaths`) listing all 315 blocks.

## Not yet ported

- Engraving and flattening do not toggle: a right-click with a pickaxe/shovel does not
  cycle `engraved`/`flattened` (nor spend durability). The states exist and bind; the
  interaction is a later logic-tier slice.
- Wooden path items do not burn (upstream's `FuelItemBlock`, 50 ticks).
- The engraved/flattened tooltip lines are in the language files but are not drawn.
- A facing path takes its template's `getOpposite()` placement rule; upstream uses
  `getClockWise()`.
- `forceSolidOn()` has no content field; the outline and collision are upstream's, the
  entity-solid flag is not reproduced.

## Install

1. Take `mcwpaths.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the
   one holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod mcwpaths.hmod`.

## Build from source

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
bash content/patches/apply.sh          # re-applies the 315 block declarations, the tab and 57 recipes
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/` holds the content generator and the in-game harness. The harness
expects a campaign checkout (`$CAMPAIGN_ROOT`) with the prepared 26.3 resources
(`$HORIZON_RES`, default `~/Desktop/horizon/.local/horizon-client/26.3`).

## Compatibility

- Horizon `1d63e0a` (see `compatibility.json` for the exact revision this
  artifact was built against).
- horizon-mixins `5a64af93`, schema 6.
- Minecraft: Java Edition 26.3.

## Credits

Macaw's Paths and Pavings 1.1.1 by Sketch Macaw and Peachy Macaw — <https://github.com/sketchmacaw/Paths-Pavings>.
The original copyright and licence notices are kept in
[LICENSE](LICENSE); [LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each
was read from.

This is an unofficial port: Horizon is not affiliated with the original author.

## Licence

MIT — see [LICENSE](LICENSE).

## Contributing

The "Not yet ported" list is the gap list; an issue or a pull request that
closes one item is welcome. Please keep the original notices and say which
slice you are working on.
