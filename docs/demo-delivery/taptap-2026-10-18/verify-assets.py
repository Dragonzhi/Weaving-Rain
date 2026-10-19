"""Check the supplied upload requirements and package only the five final PNGs."""
from pathlib import Path
import hashlib
import json
import zipfile
from PIL import Image

base = Path(__file__).resolve().parent
specs = {
    'promo-1920x1080.png': ((1920,1080),4_000_000),
    'logo-transparent.png': ((1375,594),4_000_000),
    'cover-landscape-1840x860.png': ((1840,860),4_000_000),
    'cover-portrait-1200x1800.png': ((1200,1800),4_000_000),
    'wallpaper-3840x1240.png': ((3840,1240),10_000_000),
}
files = []
for name, (expected, limit) in specs.items():
    path = base/'upload'/name
    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        assert image.format == 'PNG' and image.size == expected
        rgba = image.convert('RGBA')
        alpha = rgba.getchannel('A')
        if name == 'logo-transparent.png':
            assert image.width >= 1280 or image.height >= 720
            assert alpha.getextrema() == (0,255)
            bounds = alpha.getbbox()
            assert max(bounds[0],bounds[1],image.width-bounds[2],image.height-bounds[3]) <= 12
        else:
            assert alpha.getextrema() == (255,255)
    assert path.stat().st_size < limit
    files.append({'file':'upload/'+name,'size':list(expected),'bytes':path.stat().st_size,
                  'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'format_size_alpha_checks':'pass'})
archive = base/'WeavingRain-TapTap-assets.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as bundle:
    for name in specs:
        bundle.write(base/'upload'/name,name)
with zipfile.ZipFile(archive) as bundle:
    assert set(bundle.namelist()) == set(specs) and bundle.testzip() is None
sources=[]
for path in sorted((base/'sources').glob('*.png')):
    with Image.open(path) as image:
        sources.append({'file':'sources/'+path.name,'generated_size':list(image.size),
                        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
review = {
    'date':'2026-10-18','status':'Five assets produced and inspected; user approval and TapTap acceptance pending',
    'requirements_source':'User-supplied TapTap requirements; horizontal 460:215 and portrait 2:3 interpreted by dimensions, since pasted labels were transposed.',
    'method':'Built-in image_gen produced three reference-guided original illustrations; Godot 4.7.2 exported exact canvases and native-font title wordmark. Not a direct screenshot or simple collage.',
    'sources':sources,'exports':files,'archive':{'file':archive.name,'bytes':archive.stat().st_size,
        'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'contents_and_crc':'pass'},
    'visible_text':'Only 风织雨 and WEAVING RAIN, the Chinese/English game title. Wallpaper has no text. Transparent logo is a title wordmark, not the square application icon.',
    'font_sources':['Installed SimSun','Installed Microsoft YaHei UI'],'fonts_redistributed':False,
    'manual_review':'Agent viewed promo, both covers, transparent wordmark and wallpaper. No HUD, slogans, author credit, app icon, watermark, characters, buildings or gameplay inventions; important wallpaper subjects on the right.',
    'checks':['Native export final run exit 0, no SCRIPT ERROR in .godot/taptap-assets-20261018-final.log','Pillow decoded and verified all five PNGs','Exact dimensions and strict decimal-byte caps passed','Logo alpha and <=12px outer padding passed','ZIP has only five final images and CRC passed'],
    'limitations':['Generated illustration sources have the native dimensions recorded above; Godot resamples them to required output canvases. Not native 3840px generated artwork.','These are newly composed promotional illustrations, not gameplay captures or new in-game assets.','First export hit a float-size equality assertion in the shared picture helper; fixed by rounding title dimensions, all five re-exported and inspected.','The two remote example-image URLs could not be read by the web tool; supplied textual requirements and the attached rules image were used.','No upload, platform acceptance check, game export, commit, push, full gameplay regression or performance rerun.'],
    'prompts':'prompts.json','reproduce':'Run render-assets.gd in graphical Godot, then python docs/demo-delivery/taptap-2026-10-18/verify-assets.py',
}
(base/'review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':len(files),'zip':archive.name,'files':files},ensure_ascii=False))
