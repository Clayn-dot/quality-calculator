# quality-calculator

Select an area in Factorio 2.1 and see how many items of which quality it produces per second, minute, 10 minutes and hour. Accounts for quality modules (and their quality), productivity (modules, research, built-in), beacons, mining drills and recycler loops.

[![Support me on Boosty](https://img.shields.io/badge/Support%20me%20on-Boosty-F15F2C?style=for-the-badge)](https://boosty.to/bruklynben)

The mod is free. If you like it, you can say thanks with a one-time donation on Boosty: no subscription is needed.

## Use

Click the shortcut or press `CTRL + SHIFT + Q`, drag over the machines (Shift adds machines, Shift and right button removes them). The window shows the output of the area, what must be supplied from outside, the balance of items made and used inside, and how the recyclers are loaded. The result is a theoretical maximum (no downtime). Items the area does not make itself are supplied from outside; type how much you really supply into the "Supplied" field of the input table (Enter recalculates for the same machines). Only qualities you have unlocked are shown.

## Development

- Source: `src/quality-calculator`
- Tests: `python -X utf8 -m unittest discover -s tests` (needs `lupa`)
- Check against the real game (headless): `python -X utf8 tests/run_sim.py`
- Test stand for the real game: `python -X utf8 tools/install_testbed.py`, then `/qc-testbed unlock` in a throwaway save builds machines with signs that show the expected numbers
- Build: `python tools/build.py` (zip in `dist/`)
- Install into the game: `python tools/install.py` (only when Factorio is closed)

License: MIT. Author: bruklyn.ben.
