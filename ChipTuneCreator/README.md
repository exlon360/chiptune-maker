# ChipTune Maker

ChipTune Maker is a SwiftUI iOS chiptune sequencer with a tracker-style editor and an unsigned IPA build workflow.

## Features

- Editable note rows on the left side of the grid.
- Pulse 1, Pulse 2, Triangle, Saw Lead, Sine Pad, Pluck, Pulse 75, Noise, Kick, Snare, Hat, and Tom channels.
- Extra chip sounds: 12.5/25/50/75 pulse, triangle, saw, sine, pluck, noise, kick, snare, hat, and tom.
- Tap or drag to draw notes.
- Erase mode for removing notes.
- `Sets` button for jumping between Draft, playable Song Notes, the full `Suffocated by Hatred` song page, or More to cycle sets.
- `My Songs` menu for jumping straight into saved song pages.
- Three-finger drag on the piano roll for moving around long songs without switching edit modes.
- Loop region lane above the bar markers with draggable start/end handles and loop playback.
- Transport tempo selector with common BPM presets and one-BPM nudges.
- Key selector that folds the piano roll to only notes in the selected key/scale.
- Playable `Suffocated by Hatred` note bank with 36 parsed pitches from the song.
- Hold/drag a note horizontally to extend or shorten it, or double-tap a note to arm resizing first.
- Tap a note to select it, then adjust that note's own volume and length in the mixer.
- Growable long-song grid with +16/+64/+256, double-length, trim, and automatic edge extension while drawing or resizing.
- Tempo, channel waveform, and volume controls.
- Local project persistence with `UserDefaults`.
- GitHub raw JSON remote config from `config/chiptune-creator.json`, including channels and note patterns.
- GitHub Actions workflow for unsigned IPA artifacts.
- The song page and remote config include a 1,936-step, 4,126-event parsed `Suffocated by Hatred` full-song note map.
- `scripts/transcribe_suffocated_notes.py` regenerates the song map from the permitted source audio.

## Build IPA

Run the `Build ChipTune Creator IPA` workflow on GitHub, or push a tag like:

```bash
git tag chiptune-v0.1.0
git push origin chiptune-v0.1.0
```

The workflow produces `ChipTuneCreator-unsigned.ipa`.

Unsigned IPAs still need signing before installing on a real iPhone.
