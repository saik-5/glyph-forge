# GlyphForge

> *Forge your typography in metal*

A high-performance, GPU-accelerated text rendering engine built with Metal and Objective-C++. Features cinematic text effects inspired by movie title sequences, with smooth animations that continue even during system UI interactions.

## Features

- **GPU-Accelerated Rendering** - Pure Metal implementation for maximum performance on Apple Silicon
- **SDF (Signed Distance Field) Text** - Crisp text at any scale with efficient GPU rendering
- **Smooth Animations** - Uses dispatch source timers immune to main run loop blocking (animations continue during dock reveal, menu interactions, etc.)
- **Custom Font Support** - Load any TTF font file
- **Multiple Text Styles** - Standard, Neon, and Title rendering modes
- **4K/Retina Ready** - High-resolution atlas generation (up to 6K) for sharp rendering at any display resolution

## Demo

The included demo showcases a cinematic intro sequence with two animated titles:
1. "Forged in Objective C++"
2. "Graphics Rendered with Metal"

Each title features a dramatic sunrise effect (text brightens), holds at full intensity, then fades with a sunset effect.

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon or Intel Mac with Metal support
- Xcode Command Line Tools

## Building

```bash
make
```

## Running

### Live Preview Mode

```bash
./font_demo
```

The demo launches in fullscreen. Press `ESC` to exit fullscreen, `Space` to cycle through text styles, and `Cmd+Q` to quit.

### Pre-Render Mode (High Quality Export)

For production-quality output without compression artifacts, use pre-render mode to export frames as a PNG sequence:

```bash
./font_demo --prerender --output ./frames --width 3840 --height 2160 --fps 60
```

#### Pre-render Options

| Option | Default | Description |
|--------|---------|-------------|
| `--output DIR` | ./frames | Output directory for PNG sequence |
| `--width N` | 3840 | Output width in pixels |
| `--height N` | 2160 | Output height in pixels |
| `--fps N` | 60 | Frames per second |
| `--duration N` | 24.0 | Duration in seconds |
| `--prefix STR` | frame_ | Filename prefix |

#### Resolution Presets

| Preset | Resolution | Description |
|--------|------------|-------------|
| `--1080p` | 1920x1080 | Full HD |
| `--4k` | 3840x2160 | 4K UHD (default) |
| `--6k` | 6144x3456 | 6K |
| `--8k` | 7680x4320 | 8K UHD |

#### Examples

**4K @ 60fps (default):**
```bash
./font_demo --prerender
```

**4K @ 60fps using preset:**
```bash
./font_demo --prerender --4k
```

**1080p @ 60fps:**
```bash
./font_demo --prerender --1080p
```

**1080p @ 30fps:**
```bash
./font_demo --prerender --1080p --fps 30
```

**6K @ 60fps:**
```bash
./font_demo --prerender --6k
```

**8K @ 60fps (maximum quality):**
```bash
./font_demo --prerender --8k
```

**Custom duration (12 seconds):**
```bash
./font_demo --prerender --4k --duration 12
```

**Custom output directory:**
```bash
./font_demo --prerender --4k --output ./my_frames
```

#### Converting to Video

After pre-rendering, combine frames into a video using ffmpeg:

```bash
# High quality H.264 (widely compatible)
ffmpeg -framerate 60 -i frames/frame_%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 output.mp4

# HEVC/H.265 (smaller file, same quality)
ffmpeg -framerate 60 -i frames/frame_%05d.png -c:v libx265 -pix_fmt yuv420p -crf 18 output.mp4

# ProRes for editing (preserves quality, large file)
ffmpeg -framerate 60 -i frames/frame_%05d.png -c:v prores_ks -profile:v 3 output.mov

# Lossless for archival
ffmpeg -framerate 60 -i frames/frame_%05d.png -c:v ffv1 output.mkv
```

## Architecture

```
GlyphForge/
├── main.mm              # Demo application, animation logic, window management
├── FontRenderer.h       # Public API for the font rendering engine
├── FontRenderer.mm      # Core rendering implementation
├── PreRenderer.h        # Pre-render system for high-quality export
├── PreRenderer.mm       # Pre-render implementation (PNG sequence output)
├── Shaders.metal        # Metal shaders for SDF text rendering
├── Makefile             # Build configuration
└── OldeEnglish.ttf      # Sample custom font
```

### Key Components

- **FontRenderer** - Core C++ class handling font loading, SDF atlas generation, and Metal rendering
- **MTKView Integration** - Leverages MetalKit for display management while using custom timing for animations
- **Dispatch Source Timer** - Background timer immune to run loop blocking, ensuring smooth animations during system UI events

## Text Styles

| Style | Description |
|-------|-------------|
| Standard | Cinematic metallic bronze with sunrise/sunset animation |
| Neon | Glowing neon tubes with flicker effect |
| Title | Elegant golden text with subtle glow |

## Roadmap

Future goals for GlyphForge:

- [x] **Pre-render Export** - Export animations as PNG sequences (up to 8K)
- [x] **Live Preview** - Real-time preview with smooth animations
- [ ] **Interactive Editor** - Move and position letters freely on screen
- [ ] **Animation Timeline** - Keyframe-based animation system
- [ ] **Effect Library** - More visual effects (particles, distortion, 3D transforms)
- [ ] **Toolbox UI** - Native macOS editor interface
- [ ] **Preset System** - Save and share animation presets
- [ ] **Direct Video Export** - Export directly to MP4/ProRes without ffmpeg

## Contributing

Contributions are welcome! Areas where help is needed:

1. **New Visual Effects** - Shaders for additional text effects
2. **Editor UI** - SwiftUI or AppKit interface for the animation editor
3. **Animation System** - Keyframe interpolation and timeline
4. **Export Functionality** - Video encoding integration
5. **Documentation** - Tutorials and API documentation

### Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-effect`)
3. Commit your changes (`git commit -m 'Add amazing effect'`)
4. Push to the branch (`git push origin feature/amazing-effect`)
5. Open a Pull Request

## Technical Details

### SDF Text Rendering

GlyphForge uses Signed Distance Fields for text rendering, which provides:
- Resolution-independent text
- Efficient GPU-based outline and glow effects
- Smooth edges at any zoom level

### Animation Timing

The animation system uses wall-clock time rather than frame counting, ensuring:
- Consistent animation speed regardless of frame rate
- Correct timing even after frame drops
- Smooth playback during system events

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with Apple's Metal framework
- Inspired by cinematic title sequences
- SDF technique based on Valve's research paper

---

**GlyphForge** - *Forge your typography in metal*
