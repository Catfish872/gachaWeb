# Expedition environment and loot art

Six new environment views form three coherent outer/core pairs. Existing middle-area views remain in the environment pools. Eighteen isolated objects add six containers and twelve loot identities. Original generated PNGs are preserved; Godot AtlasTexture resources select precise regions and exclude the background separators.

Background palettes: ashen royal city (charcoal/ember/gold), verdant secret forest (moss/teal/sap gold), starlit sanctum (violet/blue/astral gold). Containers remain independent from environment art.

The final object atlas has true RGBA transparency with clear outer edges. Each object uses a measured individual rectangle to avoid neighboring sprites. Texture filtering is clipped to each region. Generation used the built-in image tool; prompts and source dimensions/hashes are retained in this directory.
