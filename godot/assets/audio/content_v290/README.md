# Thunder city licensed background music

Gate: “Treading The Unknown”; street: “Land of Misdeeds”; core: “Showdown of Misdeeds”. All composed by Jonathan Shaw (www.jshaw.co.uk), under CC BY 3.0. See LICENSES.txt for source links and attribution to retain in game credits.

Each asset is an authored-cycle loop at offset 0. Gate is 90.464 s, street 79.306 s, core 104.025 s. The full core phrase was preserved rather than shortened to a 90-second target. Loop periods were measured by waveform cross-correlation; loop beginnings correlate above 0.995 with the next repeat. A 20 ms boundary blend removes residual MP3/sample-phase discontinuity.

Rebuild from repository root with `python godot/tools/audio/build_thunder_audio.py`. Requires Python, numpy and ffmpeg. Retained originals and licenses are in `godot/tools/audio/thunder_sources`; the original composer ZIP packages contain explicit permission for commercial and non-commercial project distribution with credit. Source hashes are checked before processing. Build output targets -22 LUFS and -2 dBTP maximum using scalar gain, preserving dynamics.

Technical checks passed for decoding, frame count, integrated loudness, true peak and seam sample difference. Subjective listening and in-game playback verification remain separate release checks. Exclude the tools/source archive directory from game exports; distribute the three OGG assets and attribution.
