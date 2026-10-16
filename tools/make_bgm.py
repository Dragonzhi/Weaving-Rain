"""Prepare the selected A1 harp theme; source/license and intermediates stay cached.

Uses the audition downloader and installed numpy/ffmpeg. Only the processed Ogg
enters assets. Crossfade the final 1.5 seconds into the opening, then rotate the
loop so the file boundary itself follows consecutive original samples.
"""
import hashlib
import json

import numpy as np

from make_bgm_auditions import ROOT, OUT, SOURCE, SR, TRACKS, command, download, read, write


if __name__ == '__main__':
    SOURCE.mkdir(parents=True, exist_ok=True)
    track = download(TRACKS[0])
    raw = OUT / 'A1-full.wav'
    command(['-i', track['source_path'], '-ar', str(SR), '-ac', '2', '-c:a', 'pcm_s16le', str(raw)])
    x = read(raw)
    cross = round(1.5 * SR)
    alpha = np.linspace(0, 1, cross)[:, None]
    loop = np.concatenate((x[cross:-cross], x[-cross:] * (1-alpha) + x[:cross] * alpha))
    loop *= .5  # Leave PCM headroom before measuring the final constant gain.
    intermediate = OUT / 'A1-loop.wav'
    write(intermediate, loop)
    analysis = command(['-i', str(intermediate), '-af', 'loudnorm=I=-26:TP=-8:LRA=20:print_format=json', '-f', 'null', '-']).stderr.decode('utf-8')
    levels = json.JSONDecoder().raw_decode(analysis[analysis.rfind('{'):])[0]
    # Constant gain preserves phrasing and harp transients; no dynamic compressor.
    gain_db = min(-26-float(levels['input_i']), -8-float(levels['input_tp']))
    loop *= 10 ** (gain_db/20)
    write(intermediate, loop)
    output = ROOT / 'assets/audio/meadow_thoughts.ogg'
    command(['-i', str(intermediate), '-fflags', '+bitexact', '-c:a', 'libvorbis', '-q:a', '5', '-map_metadata', '-1',
             '-metadata', 'title=Meadow Thoughts', '-metadata', 'artist=Écrivain',
             '-metadata', 'license=CC0; https://opengameart.org/content/meadow-thoughts', str(output)])
    # Decode the actual shipped codec to inspect the wrap, not only the source PCM.
    decoded = OUT / 'A1-loop-decoded.wav'
    command(['-i', str(output), '-c:a', 'pcm_s16le', str(decoded)])
    y = read(decoded)
    jump = float(np.abs(y[0]-y[-1]).max())
    assert jump < .01 and np.abs(y).max() < .98
    preview = OUT / 'A1-loop-seam.mp3'
    seam = np.concatenate((y[-8*SR:], y[:17*SR]))
    write(OUT / 'A1-loop-seam.wav', seam)
    command(['-i', str(OUT / 'A1-loop-seam.wav'), '-c:a', 'libmp3lame', '-b:a', '192k', str(preview)])
    result = {**{k: v for k, v in track.items() if k not in ['start', 'direction']},
              'source_seconds': len(x)/SR, 'output': str(output.relative_to(ROOT)), 'seconds': len(y)/SR,
              'crossfade_seconds': cross/SR, 'gain_db_from_source': gain_db + 20*np.log10(.5), 'peak': float(np.abs(y).max()),
              'wrap_sample_jump': jump, 'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    (OUT / 'A1-loop-manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=True, indent=2))
