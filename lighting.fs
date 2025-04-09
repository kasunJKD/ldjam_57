#version 330 core

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 playerPos;      // Player position in normalized screen coordinates [0,1]
uniform float lightRadius;   // Radius of the light effect (in pixels)
uniform vec2 renderSize;     // Size of render texture (GAME_WIDTH, GAME_HEIGHT)

out vec4 finalColor;

void main() {
    // Get original texture color
    vec4 texColor = texture(texture0, fragTexCoord);

    // Convert fragment's texture coordinates to world coordinates
    vec2 fragWorldPos = fragTexCoord;
    
    // Convert player's normalized position to world coordinates
    vec2 playerWorldPos = playerPos;

    // Calculate distance from fragment to player in world space
    float dist = distance(fragWorldPos, playerPos);

    // Smooth lighting falloff
    float attenuation = smoothstep(lightRadius, lightRadius * 0.5, dist);

    // Apply lighting based on attenuation
    vec3 darkColor = texColor.rgb * colDiffuse.rgb * 0.1; // 10% brightness in darkness
    vec3 litColor = texColor.rgb * colDiffuse.rgb;

    finalColor = vec4(mix(darkColor, litColor, attenuation), texColor.a);
}
