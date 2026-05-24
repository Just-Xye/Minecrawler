shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 16.0, 1.0) = 4.0;
uniform int antialiasing : hint_range(0, 1) = 1;
uniform float aa_blend : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 screen_size = vec2(textureSize(SCREEN_TEXTURE, 0));
    
    // Calculate pixelated coordinates
    vec2 snapped = floor(uv * screen_size / pixel_size) * pixel_size / screen_size;
    
    if (antialiasing == 1) {
        // Get the pixelated color
        vec4 pixelated_color = texture(SCREEN_TEXTURE, snapped);
        
        // Calculate original color at this UV
        vec4 original_color = texture(SCREEN_TEXTURE, uv);
        
        // Calculate distance from center of pixel block
        vec2 pixel_center = snapped + (pixel_size / screen_size) * 0.5;
        vec2 dist = abs(uv - pixel_center) * (screen_size / pixel_size);
        float mix_factor = clamp((1.0 - length(dist)) * aa_blend, 0.0, 1.0);
        
        // Blend between pixelated and original for smoother edges
        COLOR = mix(original_color, pixelated_color, mix_factor);
    } else {
        // No antialiasing - sharp pixelation
        COLOR = texture(SCREEN_TEXTURE, snapped);
    }
}