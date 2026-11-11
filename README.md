# Quality Calculator

A Factorio mod: select an area and see how many items of which quality it produces per second, minute, 10 minutes and hour. It accounts for quality modules (and their quality), productivity (modules, research, built-in), beacons, mining drills and recycler loops.

Works with Factorio 2.0 and 2.1 and needs the Quality mod. Languages: English and Russian.

## Versions

| Mod version | Factorio |
| --- | --- |
| 1.0.x | 2.0 |
| 1.1.x | 2.1 |

Both come from the same source. A release of a mod has one game version, so the build script writes the right `info.json` and changelog for each. In 2.0 the quality roll is computed by the mod, in 2.1 the chances come from the game.

## Use

Click the shortcut or press `CTRL + SHIFT + Q`, drag over the machines (Shift adds machines, Shift and right button removes them). The window shows the output of the area, what must be supplied from outside, the balance of items made and used inside, and how the recyclers are loaded. The result is a theoretical maximum (no downtime). Items the area does not make itself are supplied from outside; type how much you really supply into the "Available" field of the input table (Enter recalculates for the same machines). Only qualities you have unlocked are shown.

## Layout

```
src/quality-calculator/   the mod itself (info.json, control.lua, calc*.lua, gui*.lua, locale/, graphics/)
tools/                    build.py (makes the zips), install.py (copies the zip into mods)
portal/                   text of the mod portal page
```

## Build

```
python tools/build.py          # dist/for-2.1/quality-calculator_1.1.x.zip
python tools/build.py 2.0      # dist/for-2.0/quality-calculator_1.0.x.zip
python tools/build.py all      # both
python tools/install.py        # build and copy into the game mods folder (game closed)
```

## License

MIT, see the LICENSE file.
