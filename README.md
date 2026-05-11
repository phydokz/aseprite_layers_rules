# Linked Transforms — Aseprite Extension

An Aseprite plugin that automatically generates transformed frames from source cels. Define rotations, flips, translations, and color adjustments once, and the plugin keeps all derived frames in sync as you animate.

## Use Case

When animating a character that faces multiple directions, you typically need to manually copy and mirror frames. With Linked Transforms, you mark a cel as a transformation of another cel and the plugin regenerates it automatically every time you change frame or execute a link operation.

## Features

- **Rotation** — 0–360° with nearest-neighbor interpolation
- **Flip** — horizontal and vertical mirroring
- **Translation** — pixel-level X/Y offset
- **Color adjustments** — brightness (0–200%), hue shift (0–360°), saturation (0–100%)
- **Palette snapping** — adjusted colors are mapped to the nearest palette entry, preserving indexed color mode compatibility
- **Linked frame support** — transformations propagate to all cels that share the same image data
- **Cycle detection** — prevents circular dependencies (e.g., frame A → B → A)
- **Undo-safe** — all operations run inside `app.transaction()`

## Installation

1. Download or clone this repository.
2. Copy the folder into Aseprite's extensions directory:
   - **Windows**: `%AppData%\Aseprite\extensions\`
   - **macOS**: `~/Library/Application Support/Aseprite/extensions/`
   - **Linux**: `~/.config/aseprite/extensions/`
3. Restart Aseprite.

## Usage

1. Right-click any cel in the timeline and choose **Link Transform...**.
2. Configure the transformation in the dialog:

| Control | Description |
|---|---|
| Source Frame | Frame to use as the transformation source |
| Translate X / Y | Pixel offset |
| Rotate | Rotation angle in degrees |
| Flip H / Flip V | Mirror options |
| Brightness | 0% = black · 100% = unchanged · 200% = double |
| Hue | Color shift in degrees |
| Saturation | 0–100% |

3. Click **Save**. The plugin applies the transformation immediately and re-applies it whenever you change the active site.

To remove a transformation, right-click the cel and choose **Unlink Transforms**.

## How It Works

Transformation settings are stored in layer properties under the plugin key `phydokz/aseprite_layers_rules`. On each `sitechange` event (and after `LinkCels` / Undo / Redo), the plugin reads all stored configurations and regenerates the target cels. A hash of the source image is compared against a cache to skip unchanged sources.

## Project Structure

```
aseprite_layers_rules/
├── package.json            # Extension metadata
└── linked_transforms.lua   # Plugin implementation
```

## Requirements

- [Aseprite](https://www.aseprite.org/) (any version that supports the Lua scripting API)

## License

[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — Pablo Henrick Diniz
