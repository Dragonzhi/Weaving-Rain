"""Edit newly recorded native Movie Maker footage; never reuses the old demo clips."""
from pathlib import Path
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / '.godot/trailer-20261020'
OUT = ROOT / 'docs/demo-delivery/visuals'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ff(label, *args):
    result = subprocess.run(['ffmpeg', '-hide_banner', '-y', *map(str, args)],
                            cwd=ROOT, capture_output=True)
    (CACHE / f'{label}.log').write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-5000:])
    return result.stdout


def probe(path):
    return json.loads(subprocess.check_output(
        ['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)]))


def weather_audio(edit):
    # Merge adjacent intervals of the same take; crossfade only actual sound edits.
    regions = []
    for clip in edit:
        if regions and regions[-1]['shot'] == clip['shot'] and abs(regions[-1]['start'] + regions[-1]['seconds'] - clip['start']) < .001:
            regions[-1]['seconds'] += clip['seconds']
        else:
            regions.append({k: clip[k] for k in ('shot', 'start', 'seconds')})
    overlap = .8
    args, filters, cuts, elapsed = [], [], [], 0.0
    for i, region in enumerate(regions):
        before = overlap / 2 if i else 0
        after = overlap / 2 if i < len(regions) - 1 else 0
        start = region['start'] - before
        duration = region['seconds'] + before + after
        assert start >= 0
        args += ['-ss', start, '-t', duration, '-i', CACHE / region['shot'] / 'native.avi']
        filters.append(f'[{i}:a]atrim=duration={duration},asetpts=PTS-STARTPTS[a{i}]')
        elapsed += region['seconds']
        if i < len(regions) - 1:
            cuts.append(elapsed)
    current = 'a0'
    for i in range(1, len(regions)):
        filters.append(f'[{current}][a{i}]acrossfade=d={overlap}:c1=qsin:c2=qsin[x{i}]')
        current = f'x{i}'
    # Preserve the dry opening gestures; lower the rain bed, with a smooth gain ramp.
    filters.append(f"[{current}]volume='if(lt(t,12),2,if(lt(t,12.8),2-(t-12)*1.3/0.8,0.7))':eval=frame[w]")
    path = CACHE / 'weather-crossfaded.wav'
    ff('weather-crossfades', *args, '-filter_complex', ';'.join(filters), '-map', '[w]',
       '-t', elapsed, '-ar', 48000, '-ac', 2, '-c:a', 'pcm_s16le', path)
    return {'file': str(path), 'seconds': elapsed, 'overlap_seconds': overlap,
            'cuts': cuts, 'regions': regions, 'dry_gain': 2.0, 'rain_gain': .7,
            'rain_change_db': float(20 * np.log10(.7 / 2)), 'gain_ramp_seconds': [12, 12.8]}


def music_mix(total, weather_input):
    return (
        f'[{weather_input}:a]anull[sfx];'
        f'[1:a]atrim=0:{total},asetpts=PTS-STARTPTS,volume=0.65,'
        f'afade=t=in:st=0:d=1.1,afade=t=out:st={total-2}:d=2[music];'
        f'[sfx][music]amix=inputs=2:normalize=0,alimiter=limit=0.9:level=0,'
        f'afade=t=out:st={total-1.5}:d=1.5[a]')


def contact():
    """Inspect fresh native footage before deciding the edit points."""
    for shot in ('journey', 'garden', 'storm'):
        path = CACHE / shot / 'native.avi'
        if not path.exists() or not (CACHE / shot / 'capture.json').exists():
            continue
        report = json.loads((CACHE / shot / 'capture.json').read_text(encoding='utf-8'))
        duration = float(probe(path)['format']['duration'])
        times = np.linspace(.5, min(duration - .2, report['movie_seconds'] - .1), 12)
        sheet = Image.new('RGB', (1600, 738), '#24555b')
        pen = ImageDraw.Draw(sheet)
        for i, at in enumerate(times):
            filename = CACHE / shot / f'inspect-{i:02d}.png'
            ff(f'inspect-{shot}-{i}', '-ss', at, '-i', path, '-frames:v', 1, filename)
            image = Image.open(filename).convert('RGB').resize((400, 225))
            x, y = i % 4 * 400, i // 4 * 246
            sheet.paste(image, (x, y))
            nearest = min(report['samples'], key=lambda s: abs(s['movie_seconds'] - at))
            water = '/'.join(str(round(v)) for v in nearest['water'])
            pen.text((x + 8, y + 227), f'{at:.1f}s | water {water}', fill='white')
        sheet.save(CACHE / f'{shot}-contact.jpg', quality=94)
        print(shot, 'seconds', duration, 'water', report['water'], 'outcome', report['outcome'])


def build(final_only=False, audio_only=False):
    edit = json.loads((CACHE / 'edit.json').read_text(encoding='utf-8'))
    captures = {}
    for shot, map_id in [('journey', 'level01'), ('garden', 'level05'), ('storm', 'level09')]:
        path = CACHE / shot / 'native.avi'
        report_path = CACHE / shot / 'capture.json'
        report = json.loads(report_path.read_text(encoding='utf-8'))
        assert report['layout'] == map_id and report['failures'] == report['blocked'] == 0
        assert report['input_pick_error'] < .001 and abs(report['water_error']) < .02
        assert not report['weather_injected'] and not report['sandbox']
        assert not any(report['destroyed']), 'Do not present a damaged field as a success.'
        assert report['movie_fps'] == 60 and report['native_movie_maker']
        assert not (CACHE / f'{shot}.err').read_text(encoding='utf-8').strip()
        info = probe(path)
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        assert (video['width'], video['height'], video['r_frame_rate']) == (1920, 1080, '60/1')
        assert info['format']['duration'] and float(info['format']['duration']) >= report['movie_seconds']
        assert report['elapsed'] > 0
        report.pop('samples')
        report.pop('actions')
        captures[shot] = {'report': report, 'capture_sha256': sha(report_path),
                          'native_sha256': sha(path), 'duration': info['format']['duration']}
    assert captures['garden']['report']['source_action']['created']
    assert captures['journey']['report']['water'][0] >= 250
    if final_only or audio_only:
        previous = json.loads((ROOT / 'docs/demo-delivery/trailer-review.json').read_text(encoding='utf-8'))
        assert all(previous['captures'][s]['native_sha256'] == captures[s]['native_sha256'] for s in captures)
        assert [(s['shot'], s['start'], s['seconds']) for s in previous['edit']] == [(s['shot'], s['start'], s['seconds']) for s in edit]
    encoding = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
                '-color_range', 'tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
                '-threads', '2']
    parts, total = [], 0.0
    for i, segment in enumerate(edit):
        shot, start, seconds = segment['shot'], segment['start'], segment['seconds']
        assert start >= 0 and seconds > 0
        assert start + seconds <= float(captures[shot]['duration'])
        part = CACHE / f'part-{i:02d}.mov'
        vf = 'setpts=PTS-STARTPTS,scale=in_range=full:out_range=tv:out_color_matrix=bt709,fps=30,setsar=1'
        samples = json.loads((CACHE / shot / 'capture.json').read_text(encoding='utf-8'))['samples']
        selected = [s for s in samples if start <= s['movie_seconds'] <= start + seconds]
        assert len(selected) >= 4
        assert all(s['outcome'] == 'playing' for s in selected), 'Exclude frozen result frames.'
        assert selected[-1]['simulation_seconds'] - selected[0]['simulation_seconds'] >= (selected[-1]['movie_seconds'] - selected[0]['movie_seconds']) * .98
        if shot == 'garden':
            assert start + seconds < 5.5 or start > captures[shot]['report']['source_removal']['movie_seconds'] + .05, 'Exclude native HUD close frames.'
            assert all(not any(s['destroyed']) for s in selected)
        if i == 0:
            vf += ',fade=t=in:st=0:d=0.2'
        if not final_only and not audio_only:
            ff(f'encode-part-{i}', '-ss', start, '-i', CACHE / shot / 'native.avi', '-t', seconds,
               '-vf', vf, '-af', f'asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.06,afade=t=out:st={seconds-.08}:d=0.08',
               *encoding, '-c:a', 'pcm_s16le', '-ar', 48000, '-ac', 2, part)
        assert part.exists() and abs(float(probe(part)['format']['duration']) - seconds) < .04
        segment.update({'timeline_start': total, 'timeline_end': total + seconds})
        total += seconds
        parts.append(part)
    listing = CACHE / 'trailer.ffconcat'
    listing.write_text('ffconcat version 1.0\n' + ''.join(f"file '{p.as_posix()}'\n" for p in parts), encoding='utf-8')
    # Native title asset, no new illustration or application icon in the trailer.
    logo = ROOT / 'docs/demo-delivery/taptap-2026-10-18/upload/logo-transparent.png'
    movie = OUT / 'weaving-rain-trailer.mp4'
    weather = weather_audio(edit)
    title_at = total - 3.7
    filters = (
        '[0:v]null[base];'
        f'[2:v]scale=740:-1,format=rgba,fade=t=in:st={title_at}:d=0.8:alpha=1[logo];'
        '[base][logo]overlay=x=120:y=100:shortest=1[v];' + music_mix(total, 3))
    if audio_only:
        revised = CACHE / 'audio-revised.mp4'
        packet_hash = ff('video-before-audio-remix', '-v', 'error', '-i', movie,
                         '-map', '0:v:0', '-c:v', 'copy', '-f', 'hash', '-hash', 'sha256', '-')
        ff('remix-audio', '-i', movie, '-ss', 42, '-i', ROOT / 'assets/audio/meadow_thoughts.ogg',
           '-i', weather['file'], '-filter_complex', music_mix(total, 2),
           '-map', '0:v:0', '-map', '[a]', '-c:v', 'copy', '-t', total,
           '-c:a', 'aac', '-b:a', '192k', '-ar', 48000, '-ac', 2, '-movflags', '+faststart', revised)
        after_hash = ff('video-after-audio-remix', '-v', 'error', '-i', revised,
                        '-map', '0:v:0', '-c:v', 'copy', '-f', 'hash', '-hash', 'sha256', '-')
        assert packet_hash == after_hash, 'Audio remix must preserve every encoded video packet.'
        revised.replace(movie)
        weather['video_packets_unchanged'] = packet_hash.decode().strip()
    else:
        ff('encode-final', '-f', 'concat', '-safe', 0, '-i', listing,
           '-ss', 42, '-i', ROOT / 'assets/audio/meadow_thoughts.ogg',
           '-loop', 1, '-framerate', 30, '-i', logo, '-i', weather['file'],
           '-filter_complex', filters, '-map', '[v]', '-map', '[a]', '-t', total,
           *encoding, '-c:a', 'aac', '-b:a', '192k', '-ar', 48000, '-ac', 2, '-movflags', '+faststart', movie)
    info = probe(movie)
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    assert (video['width'], video['height'], video['codec_name'], video['pix_fmt'], video['r_frame_rate']) == (1920, 1080, 'h264', 'yuv420p', '30/1')
    assert abs(float(info['format']['duration']) - total) < .15 and total >= 15
    assert movie.stat().st_size < 5_000_000_000
    ff('decode-final', '-v', 'error', '-i', movie, '-f', 'null', '-')
    pcm = ff('audio-check', '-v', 'error', '-i', movie, '-vn', '-f', 'f32le', '-acodec', 'pcm_f32le', '-')
    audio = np.frombuffer(pcm, dtype='<f4')
    peak, rms = float(np.abs(audio).max()), float(np.sqrt(np.mean(audio**2)))
    assert 0.005 < rms < .5 and peak < 1
    sheet = Image.new('RGB', (1600, 738), '#24555b')
    pen = ImageDraw.Draw(sheet)
    for i, at in enumerate(np.linspace(.5, total - .3, 12)):
        filename = CACHE / f'final-frame-{i:02d}.png'
        ff(f'final-frame-{i}', '-ss', at, '-i', movie, '-frames:v', 1, filename)
        image = Image.open(filename).convert('RGB')
        sheet.paste(image.resize((400, 225)), (i % 4 * 400, i // 4 * 246))
        pen.text((i % 4 * 400 + 8, i // 4 * 246 + 227), f'{at:.1f}s', fill='white')
    sheet.save(CACHE / 'final-contact.jpg', quality=95)
    ff('poster', '-ss', 18, '-i', movie, '-frames:v', 1, OUT / 'trailer-poster.jpg')
    review = {'date': '2026-10-20', 'status': 'Produced; technical checks passed; user review pending',
        'concept': 'A rain journey; new native shots from level01 / level05 / level09',
        'captures': captures, 'edit': edit, 'video': {
            'file': movie.relative_to(ROOT).as_posix(), 'sha256': sha(movie), 'bytes': movie.stat().st_size,
            'duration': info['format']['duration'], 'stream': video, 'audio_peak': peak, 'audio_rms': rms,
            'complete_decode': 'pass', 'title_only_at_end': True, 'old_demo_footage_reused': False,
            'native_capture_fps': 60, 'delivery_fps': 30,
            'timing': 'Native Movie Maker output time; cuts across recorded intervals, no time acceleration or optical flow.',
            'music': 'Existing CC0 Meadow Thoughts, 42s offset; native weather audio from the matching shot.'},
        'limits': ['Native offline recording is not real-time performance evidence.',
            'Recording-only camera and hidden HUD; game maps and weather rules unchanged.',
            'level09 has its authored initial tropical clouds; no injected weather.',
            'Map changes and omitted waiting use visible cuts, not one continuous run.',
            'Human audio/visual review and platform acceptance pending.'],
        'failed_attempts': ['First 30fps pilot was 1280x800 and had simulation backlog; excluded.',
            'First isolated recording copy omitted themes; stopped exact owned process, copied themes and reran.',
            'First garden take left the band active and flooded the farm; retained as first-overwater, excluded from final cut.',
            'Final garden take removes the band through the native close button and moves rain away earlier; no farm damage.'],
        'not_performed': ['Game export', 'Full gameplay regression', 'Formal performance test', 'Git commit/push', 'Platform upload']}
    if audio_only:
        previous['video'].update(review['video'])
        review = previous
        review['status'] = 'User accepted visuals; rain mix and sound edit revised; listening review pending'
    review['audio_revision'] = weather
    (ROOT / 'docs/demo-delivery/trailer-review.json').write_text(json.dumps(review, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'movie': str(movie), 'seconds': total, 'bytes': movie.stat().st_size,
                      'audio_peak': peak, 'audio_rms': rms}, ensure_ascii=False))


if __name__ == '__main__':
    import sys
    contact() if '--contact' in sys.argv else build('--final-only' in sys.argv, '--audio-only' in sys.argv)
