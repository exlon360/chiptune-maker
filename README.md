# ChipTune Maker

ChipTune Maker is a SwiftUI iOS chiptune sequencer with a tracker-style editor and an unsigned IPA build workflow.

## Features

- Editable note rows on the left side of the grid.
- Pulse, triangle, saw, noise, kick, snare, and hat channels.
- Extra chip sounds: 12.5/25/50/75 pulse, triangle, saw, sine, pluck, noise, kick, snare, hat, and tom.
- Tap or drag to draw notes.
- Erase mode for removing notes.
- Double-tap a note to arm resizing, then drag its right edge to extend or shorten it.
- Tempo, channel waveform, and volume controls.
- Local project persistence with `UserDefaults`.
- GitHub raw JSON remote config from `config/chiptune-creator.json`, including channels and note patterns.
- GitHub Actions workflow for unsigned IPA artifacts.
- The default reset pattern includes a two-bar chiptune reduction based on the requested `Suffocated by Hatred` reference.

## Build IPA

Run the `Build ChipTune Creator IPA` workflow on GitHub, or push a tag like:

```bash
git tag chiptune-v0.1.0
git push origin chiptune-v0.1.0
```

The workflow produces `ChipTuneCreator-unsigned.ipa`.

Unsigned IPAs still need signing before installing on a real iPhone.
