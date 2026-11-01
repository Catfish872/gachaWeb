# Character avatar crops

The small portraits previously displayed complete 1024×1536 bodies inside tiny controls. All ten original character images were inspected, along with user screenshots 1000015112/13/14. Dedicated face and bust regions now come from `scripts/ui/character_avatar.gd` using cached `AtlasTexture` instances. No new identity is generated, and original source PNGs are unchanged.

Face regions are individually positioned, not one generic upper-center crop. They preserve distinctive hair, hats, horns, ears, scarves and shoulder details while making the face readable. Kaldi uses the existing humanoid `kaldi-battle.png`, not the landscape dragon image. Unknown IDs return null so the UI can retain its fallback.

The ten face crops were visually inspected in a dark-background contact sheet at 200px and 40px. Ember and Zeph, the two characters most obvious in the supplied screenshots, now show their face/hair and hat clearly rather than a tiny full body. Larger artwork and battle standees are outside this helper's responsibility.

API: `get_texture(id, mode = "face")`; supported mode `bust` provides a wider head-and-upper-body composition. `region_for()` exposes exact source-space geometry for tests. Texture references are reused between UI rebuilds, `filter_clip` is enabled, and bounds are checked before loading.

`tests/test_character_avatars.gd`: 132 checks passed covering catalog coverage, AtlasTexture type, exact region, original source identity, filter clipping, cache reuse, nonempty image content, unknown-ID fallback and Kaldi source selection. Small-screen UI integration is verified separately by the shell UI owner.
