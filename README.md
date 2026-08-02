# COOPER RUN — ZX Spectrum

> **Thirty cars stand between you and victory.**

COOPER RUN is an original vertical arcade racing game written in Z80 assembly for the ZX Spectrum. Race through five timed stages, overtake the rival cars and climb from 30th position to first.

[![Game page](https://img.shields.io/badge/GitHub%20Pages-Open%20game%20page-00ffff?style=for-the-badge&labelColor=111111)](https://mmmpt.github.io/cooper-run-zx-spectrum/)
[![Download](https://img.shields.io/badge/Download-v1.0-ffff00?style=for-the-badge&labelColor=111111)](https://mmmpt.github.io/cooper-run-zx-spectrum/downloads/Cooper_Run_ZX_Spectrum_v1.0.zip)

![COOPER RUN loading screen](screenshots/01_Cooper_Run_loading_screen.png)

## The race

Five stages of 1100 metres stand between you and the finish. Beat the clock on every stage, overtake the rival cars and finish first to win. Other vehicles are ordinary traffic: they do not improve your race position, but a collision can cost valuable time and speed.

## Features

- Five timed racing stages
- Start in 30th position and fight towards first place
- Rival cars plus independent traffic
- Curving road, acceleration, braking, collisions and off-road crashes
- Easy, Normal and Hard difficulty settings
- Keyboard and Kempston joystick support
- Records table with three-letter player names
- Runs on a ZX Spectrum 48K; AY music on compatible 128K systems

## Controls

| Control | Action |
|---|---|
| `Q` | Accelerate |
| `A` | Brake |
| `O` / `P` | Turn left / right |
| Kempston up or fire | Accelerate |
| Kempston down | Brake |
| Kempston left/right | Turn |

The main menu also lets you select difficulty, control method and music.

## Download and play

Download [`Cooper_Run_ZX_Spectrum_v1.0.zip`](release/Cooper_Run_ZX_Spectrum_v1.0.zip), extract it and load `CooperRun.tap` in a real ZX Spectrum or compatible emulator.

On a real machine:

```text
LOAD ""
```

Then start the tape or the device playing the TAP image.

## Build from source

### Requirements

- Pasmo Z80 assembler
- Python 3
- GNU Make, optional

### Complete TAP

```bash
make
```

The result is written to `build/CooperRun.tap`.

Equivalent manual commands:

```bash
mkdir -p build
pasmo src/cooper.asm build/cooper.bin build/cooper.sym
python3 tools/build_tap.py \
  --loader assets/basic_loader.bin \
  --screen assets/loading_screen.scr \
  --code build/cooper.bin \
  --output build/CooperRun.tap
```

To compare the rebuilt files byte-for-byte with the supplied v1.0 release:

```bash
make verify
```

## Repository structure

```text
src/                         Main Z80 assembly source
development/udg-experiments/ Supplementary UDG experiments
development/reference-art/   Development reference images
assets/                      BASIC loader and loading screen
release/                     Ready-to-play v1.0 files
screenshots/                 Genuine emulator captures
tools/                       TAP-building utility
docs/                        Static GitHub Pages website
```

The ZX Spectrum ROM is deliberately **not included**.

## Screenshot integrity

The screenshots were captured by running the supplied TAP in a ZX Spectrum emulator. They are exact 3× nearest-neighbour enlargements of the 256 × 192 display, without smoothing, filters or invented pixels.

## Credits and AI disclosure

**Game design and programming:** MMM  
**Repository:** MmmPT

Claude AI was used as a programming assistant during development. Design choices, integration, testing and final release decisions were made by the author.

## Licensing

Source code in `src/` and `tools/` is released under the MIT License. The game title, artwork, screenshots, compiled releases and other non-code assets remain © 2026 MMM and are not covered by the MIT License. See [`LICENSE`](LICENSE) and [`ASSET-LICENSE.md`](ASSET-LICENSE.md).
