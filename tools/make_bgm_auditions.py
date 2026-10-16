"""Prepare licensed music excerpts for listening, never touch runtime audio assets.

Uses existing numpy / ffmpeg. Downloads and outputs stay under .godot/bgm-audition.
Each comparison repeats the same 12 seconds: music alone, gap, music + game weather.
"""
import concurrent.futures
import hashlib
import html
import json
import re
import subprocess
import urllib.parse
import urllib.request
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.godot/bgm-audition'
SOURCE = OUT / 'sources'
SR = 44100
SECONDS = 12
TRACKS = [
    dict(id='A1', title='Meadow Thoughts', author='Écrivain', page='meadow-thoughts', file='Meadow Thoughts.ogg', start=15, direction='空灵自然 · 竖琴'),
    dict(id='A2', title='Contemplation', author='Joth', page='contemplation-0', file='Contemplation.mp3', start=18, direction='空灵自然 · 环境铺底'),
    dict(id='B1', title='Apple Cider', author='Zane Little Music', page='apple-cider', file='apple_cider.ogg', start=25, direction='轻快田园 · 明亮节奏'),
    dict(id='B2', title='Tavern', author='yd', page='tavern-0', file='Tavern_0.ogg', start=8, direction='轻快田园 · 村落舞步'),
    dict(id='C1', title='Mystical Piano', author='Indieteur', page='mystical-piano', file='Mystical Piano_0.mp3', start=22, direction='温暖抒情 · 钢琴氛围'),
    dict(id='C2', title='Gem Popper Piano Tune', author='Mopz', page='gem-popper-piano-tune', file='gem_popper.mp3', start=10, direction='温暖抒情 · 钢琴旋律'),
]


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'WeavingRain-asset-audition/1.0'})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def download(track):
    page_url = 'https://opengameart.org/content/' + track['page']
    page_path = SOURCE / (track['id'] + '-page.html')
    if not page_path.exists(): page_path.write_bytes(fetch(page_url))
    text = page_path.read_text(encoding='utf-8')
    assert 'creativecommons.org/publicdomain/zero/1.0' in text, f"CC0 link missing: {page_url}"
    links = [html.unescape(x) for x in re.findall(r'href=[\"\']([^\"\']+)[\"\']', text)]
    links = [x for x in links if '/sites/default/files/' in x and urllib.parse.unquote(urllib.parse.urlsplit(x).path).casefold().endswith(track['file'].casefold())]
    assert links, f"Download missing: {track['file']}"
    url = urllib.parse.urljoin(page_url, links[0])
    parts = urllib.parse.urlsplit(url)
    url = urllib.parse.urlunsplit(parts._replace(path=urllib.parse.quote(parts.path, safe='/%')))
    path = SOURCE / (track['id'] + Path(track['file']).suffix.lower())
    if not path.exists(): path.write_bytes(fetch(url))
    assert path.stat().st_size > 20000, f"Empty download: {path}"
    return {**track, 'page_url': page_url, 'download_url': url, 'source_path': str(path),
            'license': 'CC0 as declared on author upload page, checked 2026-10-16',
            'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def command(args):
    return subprocess.run(['ffmpeg', '-hide_banner', '-y', *args], check=True, capture_output=True)


def read(path):
    with wave.open(str(path), 'rb') as stream:
        assert stream.getsampwidth() == 2 and stream.getframerate() == SR
        x = np.frombuffer(stream.readframes(stream.getnframes()), '<i2').reshape(-1, stream.getnchannels()).astype(float) / 32768
    return np.repeat(x, 2, axis=1) if x.shape[1] == 1 else x


def write(path, x):
    assert np.isfinite(x).all() and np.max(np.abs(x)) < .98, 'Clipped / invalid audition'
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((2, 2, SR, len(x), 'NONE', 'not compressed'))
        stream.writeframes(np.rint(x * 32767).astype('<i2').tobytes())


def weather():
    n = SECONDS * SR
    t = np.arange(n) / SR
    def repeat(name):
        x = read(ROOT / 'assets/audio' / (name + '.wav'))
        return np.tile(x, (int(np.ceil(n / len(x))), 1))[:n]
    # Identical fixed mix for all six: light wind, then distant rain gaining weight.
    wind = repeat('wind') * .12
    rain = repeat('rain') * (.4 * (1 - np.exp(-np.maximum(t - 2, 0) / 1.1)))[:, None]
    dense = repeat('rain_detail') * (.4 * (1 - np.exp(-np.maximum(t - 7, 0) / 1.1)))[:, None]
    return wind + rain + dense


def prepare(track, bed):
    raw = OUT / (track['id'] + '-raw.wav')
    command(['-ss', str(track['start']), '-i', track['source_path'], '-t', str(SECONDS), '-ar', str(SR), '-ac', '2', '-c:a', 'pcm_s16le', str(raw)])
    analysis = command(['-i', str(raw), '-af', 'loudnorm=I=-26:TP=-8:LRA=20:print_format=json', '-f', 'null', '-']).stderr.decode('utf-8')
    levels = json.JSONDecoder().raw_decode(analysis[analysis.rfind('{'):])[0]
    normalizer = ('loudnorm=I=-26:TP=-8:LRA=20:linear=true:'
                  f"measured_I={levels['input_i']}:measured_TP={levels['input_tp']}:"
                  f"measured_LRA={levels['input_lra']}:measured_thresh={levels['input_thresh']}:offset={levels['target_offset']}")
    pure = OUT / (track['id'] + '-music.wav')
    command(['-i', str(raw), '-af', normalizer, '-ar', str(SR), '-ac', '2', '-c:a', 'pcm_s16le', str(pure)])
    music = read(pure)
    assert len(music) == SECONDS * SR and np.max(np.abs(music)) > .005
    fade = np.minimum(np.arange(len(music)) / (SR * .35), 1) * np.minimum(np.arange(len(music))[::-1] / (SR * .65), 1)
    music *= fade[:, None]
    mixed = music + bed * fade[:, None]
    write(pure, music)
    write(OUT / (track['id'] + '-weather.wav'), mixed)
    combined = np.concatenate((music, np.zeros((int(.6 * SR), 2)), mixed))
    path = OUT / (track['id'] + '-comparison.wav')
    write(path, combined)
    # Compact listening copy; PCM originals and individual sections stay available.
    mp3 = path.with_suffix('.mp3')
    command(['-i', str(path), '-c:a', 'libmp3lame', '-b:a', '192k', str(mp3)])
    assert mp3.exists() and mp3.stat().st_size > 10000
    return {**track, 'comparison': str(mp3), 'seconds': len(combined) / SR,
            'music_seconds': SECONDS, 'gap_seconds': .6, 'weather_from_seconds': 12.6,
            'target_music_lufs_before_fades': -26, 'peak': float(np.abs(combined).max()),
            'rms': float(np.sqrt(np.mean(combined ** 2))),
            'output_sha256': hashlib.sha256(mp3.read_bytes()).hexdigest()}


if __name__ == '__main__':
    SOURCE.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        tracks = list(pool.map(download, TRACKS))
    bed = weather()
    results = [prepare(track, bed) for track in tracks]
    (OUT / 'manifest.json').write_text(json.dumps({'date': '2026-10-16', 'scope': 'Offline licensed excerpts; not original compositions or runtime integration', 'weather_mix': {'wind': .12, 'rain': .4, 'dense_rain': .4, 'rain_starts': 2, 'dense_starts': 7}, 'tracks': results}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps([{'id': x['id'], 'seconds': x['seconds'], 'peak': x['peak']} for x in results], indent=2))
