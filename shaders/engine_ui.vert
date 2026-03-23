#version 450

// UI vertex: 2D position + UV + color per vertex
layout(location = 0) in vec2 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;

layout(push_constant) uniform UiPC {
    vec2 screenSize;   // viewport width, height
    vec2 pad;
} ui;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;

void main() {
    // Convert pixel coords to NDC (-1..1)
    // Vulkan: Y=-1 is top, Y=+1 is bottom (no flip needed for top-left origin)
    vec2 ndc = (inPos / ui.screenSize) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
    fragUV = inUV;
    fragColor = inColor;
}
