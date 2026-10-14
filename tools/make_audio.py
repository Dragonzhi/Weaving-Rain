"""Offline sound preparation; never used by the game. Requires existing numpy.

Download the documented CC0 WAVs before running (see docs/audio-sources.md).
Selected working candidates go to assets/audio; listening comparisons stay cache.
"""
import hashlib
import json
import math
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.godot/audio-source'
OUT = ROOT / 'assets/audio'
SR = 44100
SEED = 20261014


def read(name):
    with wave.open(str(SOURCE / name), 'rb') as w:
        assert w.getsampwidth() == 2, 'Expected PCM16 source'
        x = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float)
        x = x.reshape(-1, w.getnchannels()).mean(axis=1) / 32768
        rate = w.getframerate()
    if rate != SR:
        x = np.interp(np.arange(int(len(x) * SR / rate)) * rate / SR, np.arange(len(x)), x)
    return x


def filter_audio(x, low, high):
    # Smooth frequency response; no hard spectral cut that rings around drops.
    x = x - x.mean()
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = (f / np.maximum(f, low)) ** 2 / (1 + (f / high) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * gain, n=len(x))


def level(x, rms):
    x = x * (rms / max(np.sqrt(np.mean(x*x)), 1e-9))
    return x * min(1, .45 / max(np.max(np.abs(x)), 1e-9))


def distant_rain(x):
    # A fixed overhead view hears a distant curtain, not individual nearby impacts.
    # Smooth outdoor distance EQ and soft peaks; no added noise/reverb or makeup gain.
    f = np.fft.rfftfreq(len(x), 1 / SR)
    gain = (f / np.maximum(f, 100)) ** 2
    gain *= (.45 + .55 / (1 + (f / 1200) ** 2)) / np.sqrt(1 + (f / 4200) ** 8)
    if x.ndim == 2: gain = gain[:, None]
    y = np.fft.irfft(np.fft.rfft(x - x.mean(axis=0), axis=0) * gain, n=len(x), axis=0)
    ceiling = max(3.5 * np.sqrt(np.mean(y*y)), 1e-9)
    return ceiling * np.tanh(y / ceiling)


def loop(x, seconds):
    x = x[:int(seconds * SR)]
    n = int(.6 * SR)
    t = np.linspace(0, 1, n, endpoint=False)
    blend = t*t*(3-2*t)
    if x.ndim==2: blend=blend[:,None]
    return np.concatenate((x[n:-n], x[-n:]*(1-blend) + x[:n]*blend))


def stereo_read(path):
    with wave.open(str(path),'rb') as w:
        assert w.getsampwidth()==2 and w.getframerate()==SR
        x=np.frombuffer(w.readframes(w.getnframes()),'<i2').reshape(-1,w.getnchannels()).astype(float)/32768
    return np.repeat(x,2,axis=1) if x.shape[1]==1 else x


def envelope(x):
    t = np.arange(len(x)) / SR
    return x * np.minimum(t/.012, 1) * np.minimum((len(x)/SR-t)/.045, 1)


def tone(frequencies, seconds=.32):
    t = np.arange(int(seconds*SR)) / SR
    x = np.zeros_like(t)
    for j, freq in enumerate(frequencies):
        u = np.maximum(t-j*.09, 0)
        active = t >= j*.09
        # Soft percussive drop/wood hybrid with muted second partial.
        x += active * (1-np.exp(-u*350)) * np.exp(-u*20) * (
            np.sin(2*math.pi*freq*u) + .17*np.sin(2*math.pi*freq*2.02*u))
    return level(envelope(x), .075)


metrics = {}


def write(name, x, directory=OUT):
    directory.mkdir(parents=True, exist_ok=True)
    pcm = np.rint(np.clip(x, -.99, .99)*32767).astype('<i2')
    path = directory / (name + '.wav')
    with wave.open(str(path), 'wb') as w:
        w.setparams((1 if x.ndim==1 else x.shape[1], 2, SR, len(pcm), 'NONE', 'not compressed'))
        w.writeframes(pcm.tobytes())
    metrics[name] = dict(seconds=round(len(x)/SR, 4), peak=float(np.max(np.abs(x))),
                         rms=float(np.sqrt(np.mean(x*x))),
                         seam=float(np.max(np.abs(pcm[-1].astype(float)-pcm[0].astype(float)))/32768),
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest())


wind = level(loop(filter_audio(read('wind1.wav')[SR*4:], 75, 2100), 18), .11)
raw_rain = read('rain_outdoor.wav')[SR*8:SR*30]
# Retain the accepted source, soften close leaf/ground impacts for the overhead view.
rain = loop(distant_rain(level(raw_rain-raw_rain.mean(), .105)), len(raw_rain)/SR)
write('wind', wind)
write('rain', rain)

# Promoted candidate A, including the same gentle peak handling used in the audition.
# Keep the old filename/UID: this third weather layer is now the dense rain curtain.
heavy_path=SOURCE/'rain_leaves.wav'
heavy=stereo_read(heavy_path)[SR*63:SR*77]
f=np.fft.rfftfreq(len(heavy),1/SR)[:,None]
g=(f/np.maximum(f,65))**2/np.sqrt(1+(f/9500)**8)
heavy=np.fft.irfft(np.fft.rfft(heavy-heavy.mean(axis=0),axis=0)*g,n=len(heavy),axis=0)
heavy*=.095/max(np.sqrt(np.mean(heavy*heavy)),1e-9)
heavy=.46*np.tanh(heavy/.46)
heavy*=.085/max(np.sqrt(np.mean(heavy*heavy)),1e-9)
heavy = distant_rain(heavy)
write('rain_detail',loop(heavy,14))

# Reproduce the exact five accepted v4 samples from the quantized wind file.
wind_pcm=stereo_read(OUT/'wind.wav')
for index,(start,seconds,attack) in enumerate([(4.4,.62,.22),(5.2,.65,.24),(6.4,.60,.20),(7.5,.69,.27),(8.7,.63,.23)]):
    x=wind_pcm[round(start*SR):round((start+seconds)*SR)].copy()
    t=np.linspace(0,1,len(x))[:,None]
    rise=np.clip(t/attack,0,1)
    fall=np.clip((1-t)/(1-attack),0,1)
    x*=(rise*rise*(3-2*rise))*(fall*fall*(3-2*fall))
    x*=.038/max(np.sqrt(np.mean(x*x)),1e-9)
    x*=min(1,.30/max(np.abs(x).max(),1e-9))
    write('brush' if index==0 else 'brush_'+str(index+1),x)
for name, notes in {'click':[530], 'source':[500,650], 'adequate':[680],
                    'safe':[650,820], 'full':[600,780], 'damage':[270,210],
                    'success':[600,760,920], 'failure':[320,240]}.items():
    write(name, tone(notes, .12 if name == 'click' else .38))


def pair(a, b):
    silence = np.zeros(int(SR*.6))
    return np.concatenate((envelope(a[:SR*4]), silence, envelope(b[:SR*4])))


write('试听-轻风-强风', pair(wind*.3, wind*.85), SOURCE)
write('试听-当前小雨',envelope(rain[:SR*6]*.5), SOURCE)
write('试听-当前A密雨',heavy[:SR*6]*.65,SOURCE)
shorts = []
for name in ['brush','click','source','adequate','safe','full','damage','success','failure']:
    with wave.open(str(OUT/(name+'.wav')), 'rb') as w:
        shorts.append(np.frombuffer(w.readframes(w.getnframes()), '<i2').reshape(-1,w.getnchannels()).mean(axis=1)/32768)
    shorts.append(np.zeros(int(SR*.45)))
write('试听-操作与成果', np.concatenate(shorts), SOURCE)
SOURCE.joinpath('metrics.json').write_text(json.dumps(metrics, indent=2, ensure_ascii=False), encoding='utf8')
assert all(m['peak'] < .65 for m in metrics.values())
assert all(metrics[n]['seam'] < .04 for n in ['wind','rain','rain_detail'])
print(json.dumps({'sounds':len(metrics), 'seed':SEED, 'loops':{n:metrics[n] for n in ['wind','rain','rain_detail']}}, indent=2))
