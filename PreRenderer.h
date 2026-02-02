#pragma once

#import <Metal/Metal.h>
#include <functional>
#include <string>

namespace font {
class FontRenderer;
}

// Pre-render configuration
struct PreRenderConfig {
  int width = 3840;            // Output width (default 4K)
  int height = 2160;           // Output height (default 4K)
  int fps = 60;                // Frames per second
  float duration = 24.0f;      // Total duration in seconds
  std::string outputDir;       // Output directory for frames
  std::string filenamePrefix = "frame_";  // Prefix for frame files
};

// Progress callback: (currentFrame, totalFrames, elapsedSeconds)
using PreRenderProgressCallback = std::function<void(int, int, float)>;

class PreRenderer {
public:
  PreRenderer();
  ~PreRenderer();

  // Initialize with Metal device
  bool initialize(id<MTLDevice> device);

  // Set the font renderer to use
  void setFontRenderer(font::FontRenderer* renderer);

  // Set the render callback - called for each frame with (time, commandBuffer, encoder, width, height)
  using RenderCallback = std::function<void(float, id<MTLCommandBuffer>, id<MTLRenderCommandEncoder>, int, int)>;
  void setRenderCallback(RenderCallback callback);

  // Start pre-rendering with given config
  // Returns true if successful
  bool render(const PreRenderConfig& config, PreRenderProgressCallback progress = nullptr);

  // Cancel ongoing render
  void cancel();

  // Check if currently rendering
  bool isRendering() const;

private:
  bool saveTextureAsPNG(id<MTLTexture> texture, const std::string& filepath);

  id<MTLDevice> _device;
  id<MTLCommandQueue> _commandQueue;
  id<MTLTexture> _renderTexture;
  font::FontRenderer* _fontRenderer;
  RenderCallback _renderCallback;
  bool _isRendering;
  bool _cancelRequested;
};
