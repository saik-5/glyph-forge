#import "FontRenderer.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include <algorithm>
#include <cmath>

namespace font {

// ============================================================================
// SDF GENERATION HELPERS
// ============================================================================

static float distanceToEdge(const uint8_t *bitmap, int w, int h, int x, int y,
                            int spread) {
  bool inside =
      (x >= 0 && x < w && y >= 0 && y < h) ? (bitmap[y * w + x] > 127) : false;

  float minDist = spread;

  for (int dy = -spread; dy <= spread; dy++) {
    for (int dx = -spread; dx <= spread; dx++) {
      int nx = x + dx;
      int ny = y + dy;

      if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
        bool neighborInside = bitmap[ny * w + nx] > 127;
        if (neighborInside != inside) {
          float dist = sqrtf(dx * dx + dy * dy);
          minDist = std::min(minDist, dist);
        }
      }
    }
  }

  return inside ? minDist : -minDist;
}

void FontAtlas::generateSDFFromBitmap(uint8_t *sdfData, const uint8_t *bitmap,
                                      int width, int height, int spread) {
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      float dist = distanceToEdge(bitmap, width, height, x, y, spread);
      // Normalize to 0-1 range, then to 0-255
      float normalized = (dist / spread) * 0.5f + 0.5f;
      normalized = std::max(0.0f, std::min(1.0f, normalized));
      sdfData[y * width + x] = static_cast<uint8_t>(normalized * 255);
    }
  }
}

// ============================================================================
// FONT ATLAS IMPLEMENTATION
// ============================================================================

bool FontAtlas::generate(id<MTLDevice> device, const std::string &fontName,
                         float fontSize, int atlasSize) {
  atlasSize_ = atlasSize;

  // Create Core Text font
  CFStringRef fontNameCF = CFStringCreateWithCString(nullptr, fontName.c_str(),
                                                     kCFStringEncodingUTF8);
  CTFontRef font = CTFontCreateWithName(fontNameCF, fontSize * 2,
                                        nullptr); // 2x for SDF quality
  CFRelease(fontNameCF);

  if (!font) {
    NSLog(@"Failed to create font: %s", fontName.c_str());
    return false;
  }

  // Get font metrics
  ascender_ = CTFontGetAscent(font) / 2;
  descender_ = CTFontGetDescent(font) / 2;
  lineHeight_ = (ascender_ + descender_ + CTFontGetLeading(font) / 2);

  // Create bitmap context for atlas
  std::vector<uint8_t> atlasData(atlasSize * atlasSize, 0);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGContextRef context =
      CGBitmapContextCreate(atlasData.data(), atlasSize, atlasSize, 8,
                            atlasSize, colorSpace, kCGImageAlphaNone);
  CGColorSpaceRelease(colorSpace);

  CGContextSetGrayFillColor(context, 1.0, 1.0);

  // Render glyphs
  int padding = 8;
  int spread = 6;
  int penX = padding;
  int penY = padding;
  int rowHeight = 0;

  // ASCII printable characters
  for (char32_t codepoint = 32; codepoint < 127; codepoint++) {
    UniChar character = static_cast<UniChar>(codepoint);
    CGGlyph glyph;
    CTFontGetGlyphsForCharacters(font, &character, &glyph, 1);

    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &glyph,
                                    &boundingRect, 1);

    CGSize advance;
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationDefault, &glyph,
                               &advance, 1);

    // Calculate the actual pixel bounds of the glyph
    // For descenders, origin.y is negative, so we need to account for that
    float glyphMinY = boundingRect.origin.y; // Can be negative for descenders
    float glyphMaxY = boundingRect.origin.y + boundingRect.size.height;
    float glyphMinX = boundingRect.origin.x;
    float glyphMaxX = boundingRect.origin.x + boundingRect.size.width;

    int glyphWidth = static_cast<int>(ceil(glyphMaxX - glyphMinX)) + spread * 2;
    int glyphHeight =
        static_cast<int>(ceil(glyphMaxY - glyphMinY)) + spread * 2;

    // Wrap to next row if needed
    if (penX + glyphWidth + padding > atlasSize) {
      penX = padding;
      penY += rowHeight + padding;
      rowHeight = 0;
    }

    if (penY + glyphHeight > atlasSize) {
      NSLog(@"Atlas too small for all glyphs!");
      break;
    }

    // Draw glyph - position so the glyph sits correctly in the padded box
    CGPoint position =
        CGPointMake(penX + spread - glyphMinX,
                    atlasSize - penY - glyphHeight + spread - glyphMinY);

    CTFontDrawGlyphs(font, &glyph, &position, 1, context);

    // Store glyph info (scaled back to original size)
    GlyphInfo info;
    info.u0 = static_cast<float>(penX) / atlasSize;
    info.v0 = static_cast<float>(penY) / atlasSize;
    info.u1 = static_cast<float>(penX + glyphWidth) / atlasSize;
    info.v1 = static_cast<float>(penY + glyphHeight) / atlasSize;
    info.width = glyphWidth / 2.0f;
    info.height = glyphHeight / 2.0f;
    // bearingX: offset from pen to left edge of texture box
    info.bearingX = (glyphMinX - spread) / 2.0f;
    // bearingY: distance from baseline to TOP of texture box (glyphMaxY +
    // spread)
    info.bearingY = (glyphMaxY + spread) / 2.0f;
    info.advance = advance.width / 2.0f;

    glyphs_[codepoint] = info;

    penX += glyphWidth + padding;
    rowHeight = std::max(rowHeight, glyphHeight);
  }

  CGContextRelease(context);
  CFRelease(font);

  // Generate SDF from bitmap
  std::vector<uint8_t> sdfData(atlasSize * atlasSize);
  generateSDFFromBitmap(sdfData.data(), atlasData.data(), atlasSize, atlasSize,
                        spread);

  // Create Metal texture
  MTLTextureDescriptor *desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                   width:atlasSize
                                  height:atlasSize
                               mipmapped:NO];
  desc.usage = MTLTextureUsageShaderRead;

  texture_ = [device newTextureWithDescriptor:desc];

  MTLRegion region = MTLRegionMake2D(0, 0, atlasSize, atlasSize);
  [texture_ replaceRegion:region
              mipmapLevel:0
                withBytes:sdfData.data()
              bytesPerRow:atlasSize];

  NSLog(@"Generated SDF atlas: %dx%d with %lu glyphs", atlasSize, atlasSize,
        glyphs_.size());

  return true;
}

// ============================================================================
// LOAD FONT FROM FILE (.ttf / .otf)
// ============================================================================

bool FontAtlas::generateFromFile(id<MTLDevice> device,
                                 const std::string &fontPath, float fontSize,
                                 int atlasSize) {
  atlasSize_ = atlasSize;

  // Load font data from file
  NSString *path = [NSString stringWithUTF8String:fontPath.c_str()];
  NSData *fontData = [NSData dataWithContentsOfFile:path];

  if (!fontData) {
    NSLog(@"Failed to load font file: %s", fontPath.c_str());
    return false;
  }

  // Create font from data
  CGDataProviderRef dataProvider =
      CGDataProviderCreateWithCFData((__bridge CFDataRef)fontData);
  CGFontRef cgFont = CGFontCreateWithDataProvider(dataProvider);
  CGDataProviderRelease(dataProvider);

  if (!cgFont) {
    NSLog(@"Failed to create CGFont from file: %s", fontPath.c_str());
    return false;
  }

  // Create CTFont from CGFont
  CTFontRef font =
      CTFontCreateWithGraphicsFont(cgFont, fontSize * 2, nullptr, nullptr);
  CGFontRelease(cgFont);

  if (!font) {
    NSLog(@"Failed to create CTFont from file: %s", fontPath.c_str());
    return false;
  }

  NSLog(@"Loaded custom font: %s", fontPath.c_str());

  // Get font metrics
  ascender_ = CTFontGetAscent(font) / 2;
  descender_ = CTFontGetDescent(font) / 2;
  lineHeight_ = (ascender_ + descender_ + CTFontGetLeading(font) / 2);

  // Create bitmap context for atlas
  std::vector<uint8_t> atlasData(atlasSize * atlasSize, 0);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGContextRef context =
      CGBitmapContextCreate(atlasData.data(), atlasSize, atlasSize, 8,
                            atlasSize, colorSpace, kCGImageAlphaNone);
  CGColorSpaceRelease(colorSpace);

  CGContextSetGrayFillColor(context, 1.0, 1.0);

  // Render glyphs
  int padding = 8;
  int spread = 6;
  int penX = padding;
  int penY = padding;
  int rowHeight = 0;

  // ASCII printable characters
  for (char32_t codepoint = 32; codepoint < 127; codepoint++) {
    UniChar character = static_cast<UniChar>(codepoint);
    CGGlyph glyph;
    CTFontGetGlyphsForCharacters(font, &character, &glyph, 1);

    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &glyph,
                                    &boundingRect, 1);

    CGSize advance;
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationDefault, &glyph,
                               &advance, 1);

    // Calculate the actual pixel bounds of the glyph
    float glyphMinY = boundingRect.origin.y;
    float glyphMaxY = boundingRect.origin.y + boundingRect.size.height;
    float glyphMinX = boundingRect.origin.x;
    float glyphMaxX = boundingRect.origin.x + boundingRect.size.width;

    int glyphWidth = static_cast<int>(ceil(glyphMaxX - glyphMinX)) + spread * 2;
    int glyphHeight =
        static_cast<int>(ceil(glyphMaxY - glyphMinY)) + spread * 2;

    // Wrap to next row if needed
    if (penX + glyphWidth + padding > atlasSize) {
      penX = padding;
      penY += rowHeight + padding;
      rowHeight = 0;
    }

    if (penY + glyphHeight > atlasSize) {
      NSLog(@"Atlas too small for all glyphs!");
      break;
    }

    // Draw glyph
    CGPoint position =
        CGPointMake(penX + spread - glyphMinX,
                    atlasSize - penY - glyphHeight + spread - glyphMinY);

    CTFontDrawGlyphs(font, &glyph, &position, 1, context);

    // Store glyph info (scaled back to original size)
    GlyphInfo info;
    info.u0 = static_cast<float>(penX) / atlasSize;
    info.v0 = static_cast<float>(penY) / atlasSize;
    info.u1 = static_cast<float>(penX + glyphWidth) / atlasSize;
    info.v1 = static_cast<float>(penY + glyphHeight) / atlasSize;
    info.width = glyphWidth / 2.0f;
    info.height = glyphHeight / 2.0f;
    info.bearingX = (glyphMinX - spread) / 2.0f;
    info.bearingY = (glyphMaxY + spread) / 2.0f;
    info.advance = advance.width / 2.0f;

    glyphs_[codepoint] = info;

    penX += glyphWidth + padding;
    rowHeight = std::max(rowHeight, glyphHeight);
  }

  CGContextRelease(context);
  CFRelease(font);

  // Generate SDF from bitmap
  std::vector<uint8_t> sdfData(atlasSize * atlasSize);
  generateSDFFromBitmap(sdfData.data(), atlasData.data(), atlasSize, atlasSize,
                        spread);

  // Create Metal texture
  MTLTextureDescriptor *desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                   width:atlasSize
                                  height:atlasSize
                               mipmapped:NO];
  desc.usage = MTLTextureUsageShaderRead;

  texture_ = [device newTextureWithDescriptor:desc];

  MTLRegion region = MTLRegionMake2D(0, 0, atlasSize, atlasSize);
  [texture_ replaceRegion:region
              mipmapLevel:0
                withBytes:sdfData.data()
              bytesPerRow:atlasSize];

  NSLog(@"Generated SDF atlas from file: %dx%d with %lu glyphs", atlasSize,
        atlasSize, glyphs_.size());

  return true;
}

const GlyphInfo *FontAtlas::getGlyph(char32_t codepoint) const {
  auto it = glyphs_.find(codepoint);
  return (it != glyphs_.end()) ? &it->second : nullptr;
}

// ============================================================================
// FONT RENDERER IMPLEMENTATION
// ============================================================================

bool FontRenderer::initialize(id<MTLDevice> device,
                              MTLPixelFormat colorFormat) {
  device_ = device;

  // Load shaders
  NSError *error = nil;
  NSString *shaderPath = [[NSBundle mainBundle] pathForResource:@"Shaders"
                                                         ofType:@"metal"];

  id<MTLLibrary> library;
  if (shaderPath) {
    NSString *source = [NSString stringWithContentsOfFile:shaderPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    library = [device newLibraryWithSource:source options:nil error:&error];
  } else {
    // Try loading from default library
    library = [device newDefaultLibrary];
  }

  if (!library) {
    // Last resort: load from current directory
    NSString *currentDir =
        [[NSFileManager defaultManager] currentDirectoryPath];
    shaderPath = [currentDir stringByAppendingPathComponent:@"Shaders.metal"];
    NSString *source = [NSString stringWithContentsOfFile:shaderPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    if (source) {
      library = [device newLibraryWithSource:source options:nil error:&error];
    }
  }

  if (!library) {
    NSLog(@"Failed to load shader library: %@", error);
    return false;
  }

  id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexShader"];
  id<MTLFunction> fragStandard =
      [library newFunctionWithName:@"fragmentShader"];
  id<MTLFunction> fragNeon =
      [library newFunctionWithName:@"fragmentShaderNeon"];
  id<MTLFunction> fragTitle =
      [library newFunctionWithName:@"fragmentShaderTitle"];

  // Vertex descriptor
  MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
  vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
  vertexDesc.attributes[0].offset = offsetof(Vertex, position);
  vertexDesc.attributes[0].bufferIndex = 0;
  vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
  vertexDesc.attributes[1].offset = offsetof(Vertex, texCoord);
  vertexDesc.attributes[1].bufferIndex = 0;
  vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
  vertexDesc.attributes[2].offset = offsetof(Vertex, color);
  vertexDesc.attributes[2].bufferIndex = 0;
  vertexDesc.layouts[0].stride = sizeof(Vertex);

  // Create pipelines for each style
  auto createPipeline =
      [&](id<MTLFunction> fragFunc) -> id<MTLRenderPipelineState> {
    MTLRenderPipelineDescriptor *pipelineDesc =
        [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    pipelineDesc.vertexDescriptor = vertexDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = colorFormat;
    pipelineDesc.colorAttachments[0].blendingEnabled = YES;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor =
        MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;

    NSError *err = nil;
    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&err];
    if (!pipeline) {
      NSLog(@"Failed to create pipeline: %@", err);
    }
    return pipeline;
  };

  pipelineStandard_ = createPipeline(fragStandard);
  pipelineNeon_ = createPipeline(fragNeon);
  pipelineTitle_ = createPipeline(fragTitle);

  if (!pipelineStandard_ || !pipelineNeon_ || !pipelineTitle_) {
    return false;
  }

  // Create sampler
  MTLSamplerDescriptor *samplerDesc = [[MTLSamplerDescriptor alloc] init];
  samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
  samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
  samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
  sampler_ = [device newSamplerStateWithDescriptor:samplerDesc];

  // Create buffers
  vertexBuffer_ = [device newBufferWithLength:MAX_CHARS * 4 * sizeof(Vertex)
                                      options:MTLResourceStorageModeShared];
  indexBuffer_ = [device newBufferWithLength:MAX_CHARS * 6 * sizeof(uint16_t)
                                     options:MTLResourceStorageModeShared];
  uniformBuffer_ = [device newBufferWithLength:sizeof(Uniforms)
                                       options:MTLResourceStorageModeShared];

  // Initialize uniforms with nice defaults
  uniforms_.glowColor = {0.4f, 0.6f, 1.0f, 0.8f};    // Soft blue glow
  uniforms_.outlineColor = {0.0f, 0.0f, 0.0f, 0.5f}; // Subtle dark outline
  uniforms_.glowIntensity = 0.6f;
  uniforms_.glowRadius = 0.25f;
  uniforms_.outlineWidth = 0.02f;
  uniforms_.softness = 0.5f;
  uniforms_.lightIntensity = 1.0f; // Fully lit by default

  vertices_.reserve(MAX_CHARS * 4);
  indices_.reserve(MAX_CHARS * 6);

  return true;
}

bool FontRenderer::loadFont(const std::string &fontName, float fontSize,
                            const std::string &alias) {
  std::string key = alias.empty() ? "default" : alias;

  FontAtlas atlas;
  if (!atlas.generate(device_, fontName, fontSize)) {
    return false;
  }

  atlases_[key] = std::move(atlas);
  return true;
}

bool FontRenderer::loadFontFromFile(const std::string &fontPath, float fontSize,
                                    const std::string &alias, int atlasSize) {
  std::string key = alias.empty() ? "default" : alias;

  FontAtlas atlas;
  if (!atlas.generateFromFile(device_, fontPath, fontSize, atlasSize)) {
    return false;
  }

  atlases_[key] = std::move(atlas);
  return true;
}

void FontRenderer::beginFrame(id<MTLCommandBuffer> commandBuffer,
                              id<MTLRenderCommandEncoder> encoder,
                              float viewportWidth, float viewportHeight) {
  (void)commandBuffer;
  currentEncoder_ = encoder;

  // Create orthographic projection
  float left = 0, right = viewportWidth;
  float bottom = viewportHeight, top = 0; // Flip Y for screen coords
  float near = -1, far = 1;

  uniforms_.projectionMatrix =
      simd_matrix(simd_make_float4(2.0f / (right - left), 0, 0, 0),
                  simd_make_float4(0, 2.0f / (top - bottom), 0, 0),
                  simd_make_float4(0, 0, -2.0f / (far - near), 0),
                  simd_make_float4(-(right + left) / (right - left),
                                   -(top + bottom) / (top - bottom),
                                   -(far + near) / (far - near), 1));

  uniforms_.time = time_;
  uniforms_.resolution = {viewportWidth, viewportHeight};

  vertices_.clear();
  indices_.clear();
}

void FontRenderer::drawText(const std::string &text, float x, float y,
                            const std::string &fontAlias) {
  if (text.empty())
    return;

  std::string alias = fontAlias;
  if (atlases_.find(alias) == atlases_.end()) {
    NSLog(@"Warning: Font alias '%s' not found, falling back to default",
          alias.c_str());
    alias = "default";
    if (atlases_.find(alias) == atlases_.end()) {
      NSLog(@"Error: Default font not found!");
      return;
    }
  }

  const FontAtlas &atlas = atlases_[alias];

  // Split text into lines for per-line alignment
  std::vector<std::string> lines;
  std::string currentLine;
  for (char c : text) {
    if (c == '\n') {
      lines.push_back(currentLine);
      currentLine.clear();
    } else {
      currentLine += c;
    }
  }
  lines.push_back(currentLine); // Don't forget the last line

  float penY = y;

  for (const std::string &line : lines) {
    // Calculate startX for this specific line based on alignment
    float lineWidth = measureText(line, fontAlias) * scale_;
    float startX = x;
    if (alignment_ == TextAlign::Center) {
      startX = x - lineWidth / 2;
    } else if (alignment_ == TextAlign::Right) {
      startX = x - lineWidth;
    }

    float penX = startX;

    for (char c : line) {
      const GlyphInfo *glyph = atlas.getGlyph(static_cast<char32_t>(c));
      if (!glyph)
        continue;

      float x0 = penX + glyph->bearingX * scale_;
      float y0 = penY - glyph->bearingY * scale_;
      float x1 = x0 + glyph->width * scale_;
      float y1 = y0 + glyph->height * scale_;

      uint16_t baseIndex = static_cast<uint16_t>(vertices_.size());

      vertices_.push_back({{x0, y0}, {glyph->u0, glyph->v0}, textColor_});
      vertices_.push_back({{x1, y0}, {glyph->u1, glyph->v0}, textColor_});
      vertices_.push_back({{x1, y1}, {glyph->u1, glyph->v1}, textColor_});
      vertices_.push_back({{x0, y1}, {glyph->u0, glyph->v1}, textColor_});

      indices_.push_back(baseIndex + 0);
      indices_.push_back(baseIndex + 1);
      indices_.push_back(baseIndex + 2);
      indices_.push_back(baseIndex + 0);
      indices_.push_back(baseIndex + 2);
      indices_.push_back(baseIndex + 3);

      penX += glyph->advance * scale_;
    }

    penY += atlas.getLineHeight() * scale_;
  }

  // Flush immediately with the correct font texture
  flushBatch(alias);
  vertices_.clear();
  indices_.clear();
}

void FontRenderer::flushBatch(const std::string &fontAlias) {
  if (vertices_.empty())
    return;

  std::string key = fontAlias.empty() ? "default" : fontAlias;
  auto it = atlases_.find(key);
  if (it == atlases_.end())
    return;

  // Upload vertex data
  memcpy(vertexBuffer_.contents, vertices_.data(),
         vertices_.size() * sizeof(Vertex));
  memcpy(indexBuffer_.contents, indices_.data(),
         indices_.size() * sizeof(uint16_t));
  memcpy(uniformBuffer_.contents, &uniforms_, sizeof(Uniforms));

  // Set pipeline and state
  [currentEncoder_ setRenderPipelineState:getPipelineForStyle(currentStyle_)];
  [currentEncoder_ setVertexBuffer:vertexBuffer_ offset:0 atIndex:0];
  [currentEncoder_ setVertexBuffer:uniformBuffer_ offset:0 atIndex:1];
  [currentEncoder_ setFragmentBuffer:uniformBuffer_ offset:0 atIndex:1];
  [currentEncoder_ setFragmentTexture:it->second.getTexture() atIndex:0];
  [currentEncoder_ setFragmentSamplerState:sampler_ atIndex:0];

  [currentEncoder_ drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:indices_.size()
                               indexType:MTLIndexTypeUInt16
                             indexBuffer:indexBuffer_
                       indexBufferOffset:0];
}

void FontRenderer::endFrame() {
  // Batches are now flushed per-drawText call, so just clean up
  currentEncoder_ = nil;
}

id<MTLRenderPipelineState> FontRenderer::getPipelineForStyle(TextStyle style) {
  switch (style) {
  case TextStyle::Neon:
    return pipelineNeon_;
  case TextStyle::Title:
    return pipelineTitle_;
  default:
    return pipelineStandard_;
  }
}

float FontRenderer::measureText(const std::string &text,
                                const std::string &fontAlias) {
  std::string key = fontAlias.empty() ? "default" : fontAlias;
  auto it = atlases_.find(key);
  if (it == atlases_.end())
    return 0;

  float width = 0;
  for (char c : text) {
    const GlyphInfo *glyph = it->second.getGlyph(static_cast<char32_t>(c));
    if (glyph)
      width += glyph->advance;
  }
  return width;
}

// Style setters
void FontRenderer::setColor(float r, float g, float b, float a) {
  textColor_ = {r, g, b, a};
}

void FontRenderer::setGlowColor(float r, float g, float b, float a) {
  uniforms_.glowColor = {r, g, b, a};
}

void FontRenderer::setOutlineColor(float r, float g, float b, float a) {
  uniforms_.outlineColor = {r, g, b, a};
}

void FontRenderer::setGlowIntensity(float intensity) {
  uniforms_.glowIntensity = intensity;
}

void FontRenderer::setGlowRadius(float radius) {
  uniforms_.glowRadius = radius;
}

void FontRenderer::setOutlineWidth(float width) {
  uniforms_.outlineWidth = width;
}

void FontRenderer::setSoftness(float softness) {
  uniforms_.softness = softness;
}

void FontRenderer::setStyle(TextStyle style) { currentStyle_ = style; }

void FontRenderer::setScale(float scale) { scale_ = scale; }

void FontRenderer::setAlignment(TextAlign align) { alignment_ = align; }

void FontRenderer::setLightIntensity(float intensity) {
  uniforms_.lightIntensity = intensity;
}

} // namespace font
