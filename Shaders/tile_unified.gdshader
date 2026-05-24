shader_type spatial;
render_mode specular_disabled, cull_disabled;

// ─────────────────────────────────────────────
// BEVEL
// ─────────────────────────────────────────────
uniform float bevel_size     : hint_range(0.0, 0.5)   = 0.10;
uniform float edge_softness  : hint_range(0.001, 0.2) = 0.04;
uniform float bevel_strength : hint_range(0.0, 1.0)   = 0.55;
uniform float top_only       : hint_range(0.0, 1.0)   = 0.0;

// ─────────────────────────────────────────────
// COLORS
// ─────────────────────────────────────────────
uniform vec4 base_color   : source_color = vec4(0.45, 0.45, 0.45, 1.0);
uniform vec4 reveal_color : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec4 edge_color   : source_color = vec4(0.75, 0.75, 0.75, 1.0);
uniform vec4 hold_color   : source_color = vec4(0.70, 0.70, 1.00, 1.0);
uniform vec4 flag_color   : source_color = vec4(0.926, 0.741, 0.366, 1.0);

// ─────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────
uniform float revealed : hint_range(0.0, 1.0) = 0.0;
uniform float holding  : hint_range(0.0, 1.0) = 0.0;
uniform float flagged  : hint_range(0.0, 1.0) = 0.0;

// ─────────────────────────────────────────────
// EMISSION
// ─────────────────────────────────────────────
uniform vec4  emission_color  : source_color           = vec4(0.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 0.0;

// ─────────────────────────────────────────────
void fragment() {

    // ─────────────────────────────────────────
    // FACE DETECTION
    // ─────────────────────────────────────────
    
    vec3 world_normal = normalize(
        (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz
    );

    float is_top    = step(0.9,  world_normal.y);
    float is_bottom = step(0.9, -world_normal.y);
    float is_side   = 1.0 - is_top - is_bottom;

    // ─────────────────────────────────────────
    // TILE UV FOOTPRINT
    // ─────────────────────────────────────────

    vec2 uv = VERTEX.xz + vec2(0.5);

    // ─────────────────────────────────────────
    // BEVEL MASK
    // ─────────────────────────────────────────

    float d = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );

    float bevel_mask = 1.0 - smoothstep(
        bevel_size - edge_softness,
        bevel_size + edge_softness,
        d
    );

    float face_weight = mix(
        is_top + is_side,
        is_top,
        top_only
    );

    bevel_mask *= face_weight;

    // ─────────────────────────────────────────
    // BASE COLOR LOGIC
    // ─────────────────────────────────────────

    vec3 col = base_color.rgb;

    // Top face shows reveal/emission color
    vec3 revealed_top = emission_color.rgb;

    // Side faces stay darker
    vec3 revealed_side = reveal_color.rgb;

    vec3 revealed_mix = mix(
        revealed_side,
        revealed_top,
        is_top
    );

    // Revealed state
    col = mix(col, revealed_mix, revealed);

    // Flagged state
    col = mix(
        col,
        flag_color.rgb,
        flagged * (1.0 - revealed)
    );

    // Holding state
    col = mix(
        col,
        hold_color.rgb,
        holding * (1.0 - revealed) * (1.0 - flagged)
    );

    // ─────────────────────────────────────────
    // BEVEL HIGHLIGHT
    // ─────────────────────────────────────────

    vec3 bevelled = mix(
        col,
        edge_color.rgb,
        bevel_mask
    );

    col = mix(
        col,
        bevelled,
        bevel_strength
    );

    // ─────────────────────────────────────────
    // OUTPUT
    // ─────────────────────────────────────────

    ALBEDO    = col;
    ROUGHNESS = 0.92;
    METALLIC  = 0.0;

    // Full-tile glow on ALL faces
    float glow_mask = max(revealed, flagged);

    EMISSION = emission_color.rgb
             * emission_energy
             * glow_mask;
}