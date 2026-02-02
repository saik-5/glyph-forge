# Metal Font Renderer - Makefile
# Builds the cinematic SDF font demo

CXX = clang++
TARGET = font_demo

# Source files
SOURCES = main.mm FontRenderer.mm PreRenderer.mm
HEADERS = FontRenderer.h PreRenderer.h
SHADERS = Shaders.metal

# Compiler flags
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra
CXXFLAGS += -fobjc-arc
CXXFLAGS += -fmodules

# Frameworks
FRAMEWORKS = -framework Metal -framework MetalKit -framework Cocoa
FRAMEWORKS += -framework CoreText -framework CoreGraphics -framework QuartzCore
FRAMEWORKS += -framework ImageIO -framework UniformTypeIdentifiers

# Build target
$(TARGET): $(SOURCES) $(HEADERS) $(SHADERS)
	$(CXX) $(CXXFLAGS) $(FRAMEWORKS) $(SOURCES) -o $(TARGET)
	@echo "Build complete! Run with: ./$(TARGET)"

# Debug build
debug: CXXFLAGS += -g -DDEBUG
debug: $(TARGET)

# Clean
clean:
	rm -f $(TARGET)
	rm -rf $(TARGET).dSYM

# Run
run: $(TARGET)
	./$(TARGET)

.PHONY: clean debug run
