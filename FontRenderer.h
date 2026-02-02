#pragma once

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#include <string>
#include <unordered_map>
#include <vector>

namespace font {

// ============================================================================
// STRUCTURES
// ============================================================================

struct GlyphInfo {
  float u0, v0, u1, v1;     // Texture coordinates
  float width, height;      // Glyph dimensions in pixels
  float bearingX, bearingY; // Offset from baseline
  float advance;            // Horizontal advance
};

struct Vertex {
  simd_float2 position;
  simd_float2 texCoord;
  simd_float4 color;
};

struct Uniforms {
  simd_float4x4 projectionMatrix;
  simd_float4 glowColor;
  simd_float4 outlineColor;
  float time;
  float glowIntensity;
  float glowRadius;
  float outlineWidth;
  float softness;
  simd_float2 resolution;
  float
      lightIntensity; // 0.0 = dark/unlit, 1.0 = fully lit (LOTR sunrise effect)
  float padding[1];
};

enum class TextStyle {
  Standard, // Clean with glow
  Neon,     // Cyberpunk neon tubes
  Title     // Elegant cinematic title
};

enum class TextAlign { Left, Center, Right };

// ============================================================================
// FONT ATLAS
// ============================================================================

class FontAtlas {
public:
  FontAtlas() = default;
  ~FontAtlas() = default;

  // Load from system font name (e.g., "Helvetica")
  bool generate(id<MTLDevice> device, const std::string &fontName,
                float fontSize, int atlasSize = 2048);

  // Load from font file path (e.g., "/path/to/font.ttf")
  bool generateFromFile(id<MTLDevice> device, const std::string &fontPath,
                        float fontSize, int atlasSize = 2048);

  const GlyphInfo *getGlyph(char32_t codepoint) const;
  id<MTLTexture> getTexture() const { return texture_; }
  float getLineHeight() const { return lineHeight_; }
  float getAscender() const { return ascender_; }
  float getDescender() const { return descender_; }

private:
  id<MTLTexture> texture_ = nil;
  std::unordered_map<char32_t, GlyphInfo> glyphs_;
  float lineHeight_ = 0;
  float ascender_ = 0;
  float descender_ = 0;
  int atlasSize_ = 1024;

  void generateSDFFromBitmap(uint8_t *sdfData, const uint8_t *bitmap, int width,
                             int height, int spread);
};

// ============================================================================
// FONT RENDERER
// ============================================================================

class FontRenderer {
public:
  FontRenderer() = default;
  ~FontRenderer() = default;

  bool initialize(id<MTLDevice> device, MTLPixelFormat colorFormat);

  // Load system font by name
  bool loadFont(const std::string &fontName, float fontSize,
                const std::string &alias = "");

  // Load font from .ttf/.otf file path (atlasSize can be increased for ornate
  // fonts)
  bool loadFontFromFile(const std::string &fontPath, float fontSize,
                        const std::string &alias = "", int atlasSize = 2048);

  // Core rendering
  void beginFrame(id<MTLCommandBuffer> commandBuffer,
                  id<MTLRenderCommandEncoder> encoder, float viewportWidth,
                  float viewportHeight);

  void drawText(const std::string &text, float x, float y,
                const std::string &fontAlias = "default");

  void endFrame();

  // Style settings
  void setColor(float r, float g, float b, float a = 1.0f);
  void setGlowColor(float r, float g, float b, float a = 1.0f);
  void setOutlineColor(float r, float g, float b, float a = 1.0f);
  void setGlowIntensity(float intensity);
  void setGlowRadius(float radius);
  void setOutlineWidth(float width);
  void setSoftness(float softness);
  void setStyle(TextStyle style);
  void setScale(float scale);
  void setAlignment(TextAlign align);
  void setLightIntensity(
      float intensity); // LOTR sunrise/sunset effect (0=dark, 1=lit)

  // Utilities
  float measureText(const std::string &text,
                    const std::string &fontAlias = "default");
  void setTime(float time) { time_ = time; }

private:
  id<MTLDevice> device_ = nil;
  id<MTLRenderPipelineState> pipelineStandard_ = nil;
  id<MTLRenderPipelineState> pipelineNeon_ = nil;
  id<MTLRenderPipelineState> pipelineTitle_ = nil;
  id<MTLSamplerState> sampler_ = nil;
  id<MTLBuffer> vertexBuffer_ = nil;
  id<MTLBuffer> indexBuffer_ = nil;
  id<MTLBuffer> uniformBuffer_ = nil;

  id<MTLRenderCommandEncoder> currentEncoder_ = nil;

  std::unordered_map<std::string, FontAtlas> atlases_;
  std::vector<Vertex> vertices_;
  std::vector<uint16_t> indices_;

  Uniforms uniforms_;
  simd_float4 textColor_ = {1, 1, 1, 1};
  float scale_ = 1.0f;
  float time_ = 0;
  TextStyle currentStyle_ = TextStyle::Standard;
  TextAlign alignment_ = TextAlign::Left;

  static constexpr size_t MAX_CHARS = 4096;

  void flushBatch(const std::string &fontAlias);
  id<MTLRenderPipelineState> getPipelineForStyle(TextStyle style);
};

} // namespace font
