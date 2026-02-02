#import "PreRenderer.h"
#import "FontRenderer.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <filesystem>

PreRenderer::PreRenderer()
    : _device(nil), _commandQueue(nil), _renderTexture(nil),
      _fontRenderer(nullptr), _isRendering(false), _cancelRequested(false) {}

PreRenderer::~PreRenderer() {
  _renderTexture = nil;
  _commandQueue = nil;
  _device = nil;
}

bool PreRenderer::initialize(id<MTLDevice> device) {
  _device = device;
  _commandQueue = [device newCommandQueue];
  return _commandQueue != nil;
}

void PreRenderer::setFontRenderer(font::FontRenderer *renderer) {
  _fontRenderer = renderer;
}

void PreRenderer::setRenderCallback(RenderCallback callback) {
  _renderCallback = callback;
}

bool PreRenderer::isRendering() const { return _isRendering; }

void PreRenderer::cancel() { _cancelRequested = true; }

bool PreRenderer::render(const PreRenderConfig &config,
                         PreRenderProgressCallback progress) {
  if (_isRendering) {
    NSLog(@"PreRenderer: Already rendering");
    return false;
  }

  if (!_renderCallback) {
    NSLog(@"PreRenderer: No render callback set");
    return false;
  }

  // Create output directory if it doesn't exist
  std::filesystem::path outputPath(config.outputDir);
  if (!std::filesystem::exists(outputPath)) {
    std::filesystem::create_directories(outputPath);
  }

  _isRendering = true;
  _cancelRequested = false;

  // Create render texture at target resolution
  MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                   width:config.width
                                  height:config.height
                               mipmapped:NO];
  texDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  texDesc.storageMode = MTLStorageModeManaged; // For CPU readback

  _renderTexture = [_device newTextureWithDescriptor:texDesc];
  if (!_renderTexture) {
    NSLog(@"PreRenderer: Failed to create render texture");
    _isRendering = false;
    return false;
  }

  int totalFrames = (int)(config.duration * config.fps);
  float frameTime = 1.0f / config.fps;

  NSLog(@"PreRenderer: Starting render - %d frames at %dx%d, %.1f seconds",
        totalFrames, config.width, config.height, config.duration);

  CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

  for (int frame = 0; frame < totalFrames && !_cancelRequested; frame++) {
    @autoreleasepool {
      float time = frame * frameTime;

      // Create command buffer
      id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
      if (!commandBuffer) {
        NSLog(@"PreRenderer: Failed to create command buffer at frame %d",
              frame);
        continue;
      }

      // Create render pass
      MTLRenderPassDescriptor *passDesc =
          [MTLRenderPassDescriptor renderPassDescriptor];
      passDesc.colorAttachments[0].texture = _renderTexture;
      passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
      passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
      passDesc.colorAttachments[0].clearColor =
          MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

      id<MTLRenderCommandEncoder> encoder =
          [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
      if (!encoder) {
        NSLog(@"PreRenderer: Failed to create encoder at frame %d", frame);
        continue;
      }

      // Call the render callback
      _renderCallback(time, commandBuffer, encoder, config.width, config.height);

      [encoder endEncoding];

      // Synchronize for CPU readback (managed storage mode)
      id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
      [blit synchronizeResource:_renderTexture];
      [blit endEncoding];

      [commandBuffer commit];
      [commandBuffer waitUntilCompleted];

      // Save frame as PNG
      char filename[256];
      snprintf(filename, sizeof(filename), "%s%05d.png",
               config.filenamePrefix.c_str(), frame);
      std::string filepath =
          (std::filesystem::path(config.outputDir) / filename).string();

      if (!saveTextureAsPNG(_renderTexture, filepath)) {
        NSLog(@"PreRenderer: Failed to save frame %d", frame);
      }

      // Progress callback
      if (progress) {
        float elapsed = CFAbsoluteTimeGetCurrent() - startTime;
        progress(frame + 1, totalFrames, elapsed);
      }
    }
  }

  CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
  double totalTime = endTime - startTime;

  if (_cancelRequested) {
    NSLog(@"PreRenderer: Cancelled after %.1f seconds", totalTime);
  } else {
    NSLog(@"PreRenderer: Complete - %d frames in %.1f seconds (%.1f fps "
          @"average)",
          totalFrames, totalTime, totalFrames / totalTime);
  }

  _renderTexture = nil;
  _isRendering = false;
  return !_cancelRequested;
}

bool PreRenderer::saveTextureAsPNG(id<MTLTexture> texture,
                                   const std::string &filepath) {
  NSUInteger width = texture.width;
  NSUInteger height = texture.height;
  NSUInteger bytesPerRow = width * 4; // BGRA8

  // Allocate buffer for pixel data
  std::vector<uint8_t> pixels(bytesPerRow * height);

  // Read pixels from texture
  MTLRegion region = MTLRegionMake2D(0, 0, width, height);
  [texture getBytes:pixels.data()
        bytesPerRow:bytesPerRow
         fromRegion:region
        mipmapLevel:0];

  // Convert BGRA to RGBA
  for (NSUInteger i = 0; i < width * height; i++) {
    std::swap(pixels[i * 4 + 0], pixels[i * 4 + 2]); // Swap B and R
  }

  // Create CGImage
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
      pixels.data(), width, height, 8, bytesPerRow, colorSpace,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

  if (!context) {
    CGColorSpaceRelease(colorSpace);
    return false;
  }

  CGImageRef cgImage = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);

  if (!cgImage) {
    return false;
  }

  // Save as PNG
  NSString *path = [NSString stringWithUTF8String:filepath.c_str()];
  NSURL *url = [NSURL fileURLWithPath:path];

  CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
      (__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);

  if (!dest) {
    CGImageRelease(cgImage);
    return false;
  }

  CGImageDestinationAddImage(dest, cgImage, NULL);
  bool success = CGImageDestinationFinalize(dest);

  CFRelease(dest);
  CGImageRelease(cgImage);

  return success;
}
