"""Edit native viewport captures; requires FFmpeg, Pillow and NumPy.

Run from the project root after capture-gameplay.gd and render-gameplay-cards.gd.
Capture timestamps determine playback timing; no generated/interpolated gameplay.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / '.godot/demo-media'
OUT = ROOT / 'docs/demo-delivery/visuals'
SHOTS = {
    'mountain': ('借山成云', '把湿空气迎向山坡，让雨落在需要它的地方。', 9.0, 'photo-02-hud.png'),
    'tools': ('留风聚云', '留下风带，收拢水汽，组织下一场雨。', 18.0, 'photo-02-hud.png'),
    'storm': ('海上借雨', '从外围引导雨带，在田地与水库之间作取舍。', 23.0, 'photo-02-hud.png'),
}


def ff(*args):
    result = subprocess.run(['ffmpeg', '-hide_banner', '-y', *map(str, args)], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-7000:])
    return result


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare_photos():
    for shot, (_, _, _, photo) in SHOTS.items():
        shutil.copyfile(CACHE / shot / photo, OUT / f'{shot}-source.png')


def build():
    from PIL import Image
    import numpy as np
    reports = {}
    parts = []
    encoding = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
                '-threads', '2', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2']
    for name in ['intro', *SHOTS, 'outro']:
        part = CACHE / f'{name}.mp4'
        parts.append(part)
        if name in ('intro', 'outro'):
            ff('-loop', '1', '-framerate', '24', '-i', OUT / 'cover-sunny-sea-draft.png',
               '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', '2',
               '-vf', 'fade=t=in:st=0:d=0.2,fade=t=out:st=1.85:d=0.15', *encoding, part)
            continue
        title, subtitle, start, _ = SHOTS[name]
        report = json.loads((CACHE / name / 'capture.json').read_text(encoding='utf-8'))
        assert report['failures'] == report['blocked'] == 0
        assert report['input_pick_error'] < .001 and report['sim_seconds'] >= 22
        assert report['layout'] == {'mountain':'level03','tools':'level07','storm':'level08'}[name]
        assert report['audio']['save_error'] == 0
        if name == 'tools':
            assert report['vortex_created'] and report['band_created']
        frames = report.pop('frames')
        report['clip_wall_window'] = [start, start + 7]
        report['frame_count'] = len(frames)
        report['capture_sha256'] = sha(CACHE / name / 'capture.json')
        reports[name] = report
        # Each duration comes from the real wall timestamp, including variable frame intervals.
        entries = ['ffconcat version 1.0']
        for index, frame in enumerate(frames):
            next_time = frames[index+1]['wall_seconds'] if index+1 < len(frames) else frame['wall_seconds'] + 1/24
            left, right = max(start, frame['wall_seconds']), min(start+7, next_time)
            if right <= left:
                continue
            entries += [f"file '{(CACHE / name / frame['file']).as_posix()}'", f'duration {right-left:.9f}']
        entries.append(entries[-2])  # demuxer needs a final repeated file to honor last duration
        listing = CACHE / f'{name}.ffconcat'
        listing.write_text('\n'.join(entries)+'\n', encoding='utf-8')
        ass = CACHE / f'{name}.ass'
        ass.write_text(f'''[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,SimSun,56,&H00E3F5F0,&H00E3F5F0,&H604A686B,&H00000000,0,0,0,0,100,100,0,0,1,0.5,0,7,0,0,0,1
Style: Body,Microsoft YaHei UI,23,&H00E3F5F0,&H00E3F5F0,&H604A686B,&H00000000,0,0,0,0,100,100,0,0,1,0.5,0,7,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:07.00,Title,,0,0,0,,{{\\pos(108,166)\\fad(150,150)}}{title}
Dialogue: 0,0:00:00.00,0:00:07.00,Body,,0,0,0,,{{\\pos(112,249)\\fad(150,150)}}{subtitle}
''', encoding='utf-8')
        ff('-f', 'concat', '-safe', '0', '-i', listing, '-ss', start,
           '-i', CACHE / name / 'weather.wav', '-t', '7',
           '-vf', f'ass=.godot/demo-media/{name}.ass,fps=24,fade=t=in:st=0:d=0.15,fade=t=out:st=6.85:d=0.15',
           '-af', 'afade=t=in:st=0:d=0.15,afade=t=out:st=6.85:d=0.15',
           *encoding, part)
    concat = CACHE / 'edit.ffconcat'
    concat.write_text('ffconcat version 1.0\n' + ''.join(f"file '{p.as_posix()}'\n" for p in parts), encoding='utf-8')
    movie = OUT / 'weaving-rain-demo.mp4'
    ff('-f', 'concat', '-safe', '0', '-i', concat, '-i', ROOT / 'assets/audio/meadow_thoughts.ogg',
       '-filter_complex', '[0:a]volume=0.9[sfx];[1:a]atrim=0:25,asetpts=PTS-STARTPTS,volume=0.8[music];'
       '[sfx][music]amix=inputs=2:normalize=0,alimiter=limit=0.95:level=0,'
       'afade=t=in:st=0:d=0.7,afade=t=out:st=23.5:d=1.5[mix]',
       '-map', '0:v', '-map', '[mix]', '-t', '25', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', movie)
    probe = subprocess.run(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(movie)],
                           capture_output=True, check=True)
    info = json.loads(probe.stdout)
    assert abs(float(info['format']['duration'])-25) < .1
    video = next(s for s in info['streams'] if s['codec_type']=='video')
    assert (video['width'],video['height'],video['codec_name'],video['pix_fmt']) == (1920,1080,'h264','yuv420p')
    ff('-v','error','-i',movie,'-f','null','-')
    pcm = ff('-v','error','-i',movie,'-vn','-f','f32le','-acodec','pcm_f32le','-')
    values = np.frombuffer(pcm.stdout, dtype='<f4')
    peak = float(np.abs(values).max())
    assert peak < 1 and float(np.sqrt(np.mean(values**2))) > .005
    samples=[]
    for time in [1,3,6,10,13,17,20,24]:
        path=CACHE/f'video-review-{time:02d}.png'
        ff('-ss',time,'-i',movie,'-frames:v','1',path)
        samples.append(path)
    contact=Image.new('RGB',(1280,360))
    for i,path in enumerate(samples):
        im=Image.open(path).convert('RGB').resize((320,180))
        contact.paste(im,((i%4)*320,(i//4)*180))
    contact.save(CACHE/'video-review.png')
    poster_checks={}
    for shot in SHOTS:
        source=np.asarray(Image.open(OUT/f'{shot}-source.png').convert('RGB'))
        card=np.asarray(Image.open(OUT/f'{shot}-gameplay.png').convert('RGB'))
        assert source.shape==card.shape==(1080,1920,3)
        assert np.array_equal(source[330:960],card[330:960])
        poster_checks[shot]={'size':[1920,1080],'gameplay_rows_330_959_unchanged':True,
                             'source_sha256':sha(OUT/f'{shot}-source.png'),'card_sha256':sha(OUT/f'{shot}-gameplay.png')}
    evidence={'date':'2026-10-16','status':'Produced and technically checked; user visual/auditory review pending',
              'credit':'ZLOONG · 智龙','base_commit':'7a28040','dirty_worktree':True,
              'capture':reports,'posters':poster_checks,'video':{'file':str(movie.relative_to(ROOT)).replace('\\','/'),
              'sha256':sha(movie),'duration':info['format']['duration'],'video_stream':video,
              'audio_peak':peak,'audio_rms':float(np.sqrt(np.mean(values**2))),'decode':'pass',
              'edit':'2s accepted cover + 3x7s gameplay + 2s cover. Actual wall timestamp playback; no optical flow or time acceleration.',
              'mix':'Continuous existing Meadow Thoughts at gain .8 + matching native SFX .9; short audio fades, ceiling .95. Game audio assets/config unchanged.'},
              'limitations':['Readback/JPEG recording slows simulation; not a performance benchmark.',
              'Selected segments end while playing; not complete-level or nine-level acceptance.',
              'level08 uses its normal authored tropical opening clouds; no weather injection.',
              'One reshoot launch used incomplete map paths and fell back to standard; discarded. Final map ID and advancement assertions added.'],
              'not_performed':['Game export','Git commit or push','TapTap upload','Full rules or performance rerun']}
    (ROOT/'docs/demo-delivery/media-review.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'video':str(movie),'duration':info['format']['duration'],'peak':peak,'posters':list(poster_checks)},ensure_ascii=False))


if __name__ == '__main__':
    import sys
    prepare_photos() if '--photos' in sys.argv else build()
