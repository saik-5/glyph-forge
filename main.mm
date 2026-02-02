#include "FontRenderer.h"
#include "PreRenderer.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <cmath>
#include <string>

// ============================================================================
// DEMO VIEW CONTROLLER
// ============================================================================

@interface FontDemoView : MTKView <MTKViewDelegate>
@property(nonatomic) font::FontRenderer *fontRenderer;
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property(nonatomic) float totalTime;
@property(nonatomic) int currentStyle;
@property(nonatomic, strong) dispatch_source_t renderTimer;
@property(nonatomic, strong) dispatch_queue_t renderQueue;
@property(nonatomic) BOOL renderTimerRunning;
@property(atomic)
    BOOL framePending; // Atomic flag to prevent frame queue buildup
@end

@implementation FontDemoView

- (void)startDisplayLink {
  if (_renderTimerRunning)
    return;

  // Create a high-priority background queue for rendering
  _renderQueue =
      dispatch_queue_create("com.fontdemo.render", DISPATCH_QUEUE_SERIAL);
  dispatch_set_target_queue(
      _renderQueue, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));

  // Create timer source on the render queue (NOT main queue)
  _renderTimer =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _renderQueue);

  // 120 Hz = ~8.33ms interval
  uint64_t interval = NSEC_PER_SEC / 120;
  dispatch_source_set_timer(_renderTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                            interval, interval / 10);

  __block FontDemoView *blockSelf = self;
  dispatch_source_set_event_handler(_renderTimer, ^{
    // Skip if a frame is already queued (prevents buildup during dock reveal)
    if (blockSelf.framePending)
      return;
    blockSelf.framePending = YES;

    // Dispatch to main thread for drawable presentation
    dispatch_async(dispatch_get_main_queue(), ^{
      [blockSelf renderFrameOnRenderThread];
      blockSelf.framePending = NO;
    });
  });

  dispatch_resume(_renderTimer);
  _renderTimerRunning = YES;
  NSLog(@"Dispatch render timer started at 120 Hz on background queue");
}

- (void)stopDisplayLink {
  if (_renderTimerRunning && _renderTimer) {
    dispatch_source_cancel(_renderTimer);
    _renderTimer = nil;
    _renderQueue = nil;
    _renderTimerRunning = NO;
    NSLog(@"Dispatch render timer stopped");
  }
}

// Render on background thread - Metal is thread-safe
- (void)renderFrameOnRenderThread {
  @autoreleasepool {
    // Frame timing
    static CFAbsoluteTime startTime = 0;
    static int frameCount = 0;
    static CFAbsoluteTime lastFPSLog = 0;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // Initialize start time on first frame
    if (startTime == 0) {
      startTime = now;
      lastFPSLog = now;
    }

    frameCount++;

    // Log FPS every 10 seconds
    if (now - lastFPSLog > 10.0) {
      double fps = frameCount / (now - lastFPSLog);
      NSLog(@"FPS: %.1f", fps);
      frameCount = 0;
      lastFPSLog = now;
    }

    // Use actual wall clock time for animation (not assumed frame rate)
    _totalTime = (float)(now - startTime);
    _fontRenderer->setTime(_totalTime);

    // Get drawable - this works from any thread
    id<CAMetalDrawable> drawable = self.currentDrawable;
    if (!drawable) {
      return;
    }

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    if (!commandBuffer) {
      return;
    }

    // Create render pass descriptor
    MTLRenderPassDescriptor *passDesc =
        [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor =
        MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
    if (!encoder) {
      return;
    }

    CGSize size = self.drawableSize;
    _fontRenderer->beginFrame(commandBuffer, encoder, size.width, size.height);

    // Style switching
    font::TextStyle style;
    switch (_currentStyle) {
    case 0:
      style = font::TextStyle::Standard;
      break;
    case 1:
      style = font::TextStyle::Neon;
      break;
    case 2:
      style = font::TextStyle::Title;
      break;
    default:
      style = font::TextStyle::Standard;
      break;
    }
    _fontRenderer->setStyle(style);

    // Cinematic intro sequence
    float centerX = size.width / 2;
    float centerY = size.height / 2;

    _fontRenderer->setAlignment(font::TextAlign::Center);
    _fontRenderer->setScale(2.0f);
    _fontRenderer->setGlowIntensity(5.5f);
    _fontRenderer->setGlowRadius(0.4f);
    _fontRenderer->setOutlineColor(0.0f, 0.0f, 0.0f, 0.0f);

    float lightIntensity = 0.0f;
    std::string text;

    // Loop animation every 24 seconds (12s per text sequence)
    // Each sequence: 0-5s sunrise, 5-7s hold, 7-11s sunset, 11-12s dark pause
    float animTime = fmod(_totalTime, 24.0f);

    if (animTime < 12.0f) {
      // First sequence: "Forged in Objective C++"
      text = "Forged\nin\nObjective C++";
      if (animTime < 5.0f) {
        lightIntensity = animTime / 5.0f; // Sunrise over 5s
      } else if (animTime < 7.0f) {
        lightIntensity = 1.0f; // Hold for 2s
      } else if (animTime < 11.0f) {
        lightIntensity = 1.0f - (animTime - 7.0f) / 4.0f; // Sunset over 4s
      } else {
        text = ""; // Dark pause 1s
        lightIntensity = 0.0f;
      }
    } else {
      // Second sequence: "Graphics Rendered with Metal"
      float t = animTime - 12.0f;
      text = "Graphics Rendered\nwith\nMetal";
      if (t < 5.0f) {
        lightIntensity = t / 5.0f; // Sunrise over 5s
      } else if (t < 7.0f) {
        lightIntensity = 1.0f; // Hold for 2s
      } else if (t < 11.0f) {
        lightIntensity = 1.0f - (t - 7.0f) / 4.0f; // Sunset over 4s
      } else {
        text = ""; // Dark pause 1s
        lightIntensity = 0.0f;
      }
    }

    lightIntensity = std::max(0.0f, std::min(1.0f, lightIntensity));
    lightIntensity =
        lightIntensity * lightIntensity * (3.0f - 2.0f * lightIntensity);
    _fontRenderer->setLightIntensity(lightIntensity);

    if (!text.empty()) {
      _fontRenderer->setColor(0.9f, 0.7f, 0.1f, 1.0f);
      _fontRenderer->setGlowColor(0.8f, 0.45f, 0.05f, 1.0f);
      _fontRenderer->drawText(text, centerX, centerY, "custom");
    }

    _fontRenderer->endFrame();

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
  }
}

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
  self = [super initWithFrame:frame device:device];
  if (self) {
    self.delegate = self;
    self.clearColor =
        MTLClearColorMake(1.0, 0.0, 0.0, 1.0); // DEBUG: RED BACKGROUND
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;

    // Keep MTKView's display link running for proper layer presentation
    // Our dispatch timer handles the actual rendering via dispatch to main
    // queue
    self.paused = NO;
    self.enableSetNeedsDisplay = NO;
    self.preferredFramesPerSecond = 120;

    _fontRenderer = new font::FontRenderer();

    if (!_fontRenderer->initialize(device, self.colorPixelFormat)) {
      NSLog(@"Failed to initialize font renderer");
      return nil;
    }

    // Load fonts for 4K rendering
    // Get path to custom font (in same directory as executable)
    NSString *currentDir =
        [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *customFontPath =
        [currentDir stringByAppendingPathComponent:@"OldeEnglish.ttf"];

    // Load custom font for title
    // 6144 (6K) atlas for maximum sharpness
    if (!_fontRenderer->loadFontFromFile([customFontPath UTF8String], 96,
                                         "custom", 6144)) {
      NSLog(@"Could not load custom font, falling back to system font");
      _fontRenderer->loadFont("Times New Roman", 96, "custom");
    }

    // System fonts for other text
    _fontRenderer->loadFont("Helvetica Neue", 72, "default");
    _fontRenderer->loadFont("Menlo", 64, "mono");

    // Create command queue once
    _commandQueue = [device newCommandQueue];

    _totalTime = 0;
    _currentStyle = 0;
  }
  return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)dealloc {
  [self stopDisplayLink];
  delete _fontRenderer;
}
#pragma clang diagnostic pop

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect; // Suppress unused warning
  [super drawRect:dirtyRect];
}

- (void)keyDown:(NSEvent *)event {
  NSLog(@"KeyDown: keyCode=%hu, characters='%@'", event.keyCode,
        event.characters);

  // Cycle through styles with spacebar
  if (event.keyCode == 49) { // Space
    _currentStyle = (_currentStyle + 1) % 3;
    NSLog(@"Style changed to: %d", _currentStyle);
  }
  // ESC to exit fullscreen
  else if (event.keyCode == 53) {
    if (self.window.styleMask & NSWindowStyleMaskFullScreen) {
      [self.window toggleFullScreen:nil];
    }
  }
}

- (void)mouseMoved:(NSEvent *)event {
  // Throttled logging - only log once per second
  static CFAbsoluteTime lastMouseLog = 0;
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - lastMouseLog > 1.0) {
    NSLog(@"MouseMoved (throttled): (%.1f, %.1f)", event.locationInWindow.x,
          event.locationInWindow.y);
    lastMouseLog = now;
  }
}

- (void)mouseDown:(NSEvent *)event {
  NSLog(@"MouseDown at: (%.1f, %.1f)", event.locationInWindow.x,
        event.locationInWindow.y);
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
  (void)view;
  // Rendering is done on background thread via renderFrameOnRenderThread
}

@end

// ============================================================================
// APP DELEGATE
// ============================================================================

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  // 4K resolution for cinematic quality
  NSRect frame = NSMakeRect(0, 0, 3840, 2160);

  self.window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable |
                           NSWindowStyleMaskMiniaturizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];

  self.window.title = @"Metal Font Renderer - Cinematic Demo";

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (!device) {
    NSLog(@"Metal is not supported on this device");
    [NSApp terminate:nil];
    return;
  }

  FontDemoView *metalView = [[FontDemoView alloc] initWithFrame:frame
                                                         device:device];
  if (!metalView) {
    NSLog(@"ERROR: Failed to create metalView");
    [NSApp terminate:nil];
    return;
  }

  NSLog(@"MetalView created: %@, device=%@", metalView, metalView.device);
  NSLog(@"MetalView delegate: %@", metalView.delegate);
  NSLog(@"MetalView paused: %d", metalView.paused);
  NSLog(@"MetalView drawableSize: %.0fx%.0f", metalView.drawableSize.width,
        metalView.drawableSize.height);

  self.window.contentView = metalView;

  // Center on screen
  [self.window center];
  [self.window makeKeyAndOrderFront:nil];
  [self.window makeFirstResponder:metalView];

  NSLog(@"Window shown, drawableSize now: %.0fx%.0f",
        metalView.drawableSize.width, metalView.drawableSize.height);

  // Use dispatch source timer on background queue - completely independent of
  // main run loop so it continues running during dock reveal, menu tracking,
  // fullscreen transitions, etc.
  [metalView startDisplayLink];

  // Launch in fullscreen for cinematic experience
  [self.window toggleFullScreen:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
  return YES;
}

@end

// ============================================================================
// PRE-RENDER MODE
// ============================================================================

void printUsage(const char *programName) {
  printf("GlyphForge - Forge your typography in metal\n\n");
  printf("Usage:\n");
  printf("  %s                      Run in live preview mode\n", programName);
  printf("  %s --prerender [options]  Pre-render to image sequence\n\n", programName);
  printf("Pre-render options:\n");
  printf("  --output DIR     Output directory (default: ./frames)\n");
  printf("  --width N        Output width (default: 3840)\n");
  printf("  --height N       Output height (default: 2160)\n");
  printf("  --fps N          Frames per second (default: 60)\n");
  printf("  --duration N     Duration in seconds (default: 24.0)\n");
  printf("  --prefix STR     Filename prefix (default: frame_)\n\n");
  printf("Resolution presets:\n");
  printf("  --1080p          1920x1080 (Full HD)\n");
  printf("  --4k             3840x2160 (4K UHD) - default\n");
  printf("  --6k             6144x3456 (6K)\n");
  printf("  --8k             7680x4320 (8K UHD)\n\n");
  printf("Examples:\n");
  printf("  %s --prerender --4k                    4K @ 60fps\n", programName);
  printf("  %s --prerender --6k --fps 30           6K @ 30fps\n", programName);
  printf("  %s --prerender --1080p --duration 12   1080p, 12 seconds\n", programName);
  printf("\nAfter pre-rendering, combine frames with ffmpeg:\n");
  printf("  ffmpeg -framerate 60 -i frames/frame_%%05d.png -c:v libx264 -pix_fmt yuv420p output.mp4\n");
}

int runPreRender(const PreRenderConfig &config) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      NSLog(@"Metal is not supported on this device");
      return 1;
    }

    // Initialize font renderer
    font::FontRenderer *fontRenderer = new font::FontRenderer();
    if (!fontRenderer->initialize(device, MTLPixelFormatBGRA8Unorm)) {
      NSLog(@"Failed to initialize font renderer");
      delete fontRenderer;
      return 1;
    }

    // Load fonts
    NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *customFontPath = [currentDir stringByAppendingPathComponent:@"OldeEnglish.ttf"];

    if (!fontRenderer->loadFontFromFile([customFontPath UTF8String], 96, "custom", 6144)) {
      NSLog(@"Could not load custom font, falling back to system font");
      fontRenderer->loadFont("Times New Roman", 96, "custom");
    }

    // Initialize pre-renderer
    PreRenderer preRenderer;
    if (!preRenderer.initialize(device)) {
      NSLog(@"Failed to initialize pre-renderer");
      delete fontRenderer;
      return 1;
    }

    // Set up render callback with the animation logic
    // Note: Standard style has the lightIntensity-based sunrise/sunset animation
    preRenderer.setRenderCallback([fontRenderer](float time, id<MTLCommandBuffer> commandBuffer, id<MTLRenderCommandEncoder> encoder, int width, int height) {
      fontRenderer->setTime(time);
      fontRenderer->beginFrame(commandBuffer, encoder, width, height);
      fontRenderer->setStyle(font::TextStyle::Standard);

      float centerX = width / 2.0f;
      float centerY = height / 2.0f;

      fontRenderer->setAlignment(font::TextAlign::Center);
      fontRenderer->setScale(2.0f);
      fontRenderer->setGlowIntensity(5.5f);
      fontRenderer->setGlowRadius(0.4f);
      fontRenderer->setOutlineColor(0.0f, 0.0f, 0.0f, 0.0f);

      float lightIntensity = 0.0f;
      std::string text;

      float animTime = fmod(time, 24.0f);

      if (animTime < 12.0f) {
        text = "Forged\nin\nObjective C++";
        if (animTime < 5.0f) {
          lightIntensity = animTime / 5.0f;
        } else if (animTime < 7.0f) {
          lightIntensity = 1.0f;
        } else if (animTime < 11.0f) {
          lightIntensity = 1.0f - (animTime - 7.0f) / 4.0f;
        } else {
          text = "";
          lightIntensity = 0.0f;
        }
      } else {
        float t = animTime - 12.0f;
        text = "Graphics Rendered\nwith\nMetal";
        if (t < 5.0f) {
          lightIntensity = t / 5.0f;
        } else if (t < 7.0f) {
          lightIntensity = 1.0f;
        } else if (t < 11.0f) {
          lightIntensity = 1.0f - (t - 7.0f) / 4.0f;
        } else {
          text = "";
          lightIntensity = 0.0f;
        }
      }

      lightIntensity = std::max(0.0f, std::min(1.0f, lightIntensity));
      lightIntensity = lightIntensity * lightIntensity * (3.0f - 2.0f * lightIntensity);
      fontRenderer->setLightIntensity(lightIntensity);

      if (!text.empty()) {
        fontRenderer->setColor(0.9f, 0.7f, 0.1f, 1.0f);
        fontRenderer->setGlowColor(0.8f, 0.45f, 0.05f, 1.0f);
        fontRenderer->drawText(text, centerX, centerY, "custom");
      }

      fontRenderer->endFrame();
    });

    // Progress callback
    auto progressCallback = [](int current, int total, float elapsed) {
      float percent = (float)current / total * 100.0f;
      float eta = (elapsed / current) * (total - current);
      printf("\rRendering: %d/%d (%.1f%%) - ETA: %.1fs    ", current, total, percent, eta);
      fflush(stdout);
    };

    printf("GlyphForge Pre-Render\n");
    printf("Output: %s\n", config.outputDir.c_str());
    printf("Resolution: %dx%d @ %d fps\n", config.width, config.height, config.fps);
    printf("Duration: %.1f seconds (%d frames)\n\n", config.duration, (int)(config.duration * config.fps));

    bool success = preRenderer.render(config, progressCallback);
    printf("\n");

    if (success) {
      printf("\nPre-render complete!\n");
      printf("Frames saved to: %s\n", config.outputDir.c_str());
      printf("\nTo create video, run:\n");
      printf("  ffmpeg -framerate %d -i %s/%s%%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 output.mp4\n",
             config.fps, config.outputDir.c_str(), config.filenamePrefix.c_str());
    }

    delete fontRenderer;
    return success ? 0 : 1;
  }
}

// ============================================================================
// MAIN
// ============================================================================

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    // Parse command line arguments
    bool preRenderMode = false;
    PreRenderConfig config;
    config.outputDir = "./frames";
    config.width = 3840;
    config.height = 2160;
    config.fps = 60;
    config.duration = 24.0f;
    config.filenamePrefix = "frame_";

    for (int i = 1; i < argc; i++) {
      std::string arg = argv[i];

      if (arg == "--help" || arg == "-h") {
        printUsage(argv[0]);
        return 0;
      } else if (arg == "--prerender") {
        preRenderMode = true;
      } else if (arg == "--output" && i + 1 < argc) {
        config.outputDir = argv[++i];
      } else if (arg == "--width" && i + 1 < argc) {
        config.width = std::stoi(argv[++i]);
      } else if (arg == "--height" && i + 1 < argc) {
        config.height = std::stoi(argv[++i]);
      } else if (arg == "--fps" && i + 1 < argc) {
        config.fps = std::stoi(argv[++i]);
      } else if (arg == "--duration" && i + 1 < argc) {
        config.duration = std::stof(argv[++i]);
      } else if (arg == "--prefix" && i + 1 < argc) {
        config.filenamePrefix = argv[++i];
      } else if (arg == "--1080p") {
        config.width = 1920; config.height = 1080;
      } else if (arg == "--4k") {
        config.width = 3840; config.height = 2160;
      } else if (arg == "--6k") {
        config.width = 6144; config.height = 3456;
      } else if (arg == "--8k") {
        config.width = 7680; config.height = 4320;
      }
    }

    // Pre-render mode
    if (preRenderMode) {
      return runPreRender(config);
    }

    // Live preview mode
    NSApplication *app = [NSApplication sharedApplication];
    app.activationPolicy = NSApplicationActivationPolicyRegular;

    AppDelegate *delegate = [[AppDelegate alloc] init];
    app.delegate = delegate;

    // Create menu bar
    NSMenu *menuBar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *quitItem =
        [[NSMenuItem alloc] initWithTitle:@"Quit"
                                   action:@selector(terminate:)
                            keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    appMenuItem.submenu = appMenu;

    app.mainMenu = menuBar;

    [app activateIgnoringOtherApps:YES];
    [app run];
  }
  return 0;
}
