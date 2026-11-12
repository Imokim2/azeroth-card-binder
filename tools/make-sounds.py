"""Original, deterministic UI sound design. Run with numpy, scipy and soundfile 0.13.1.

No recordings or third-party samples. Ogg files ship with the addon; a WAV listening
reel and timing manifest go to ignored outputs/sound-preview for review.
"""
import json
import wave
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfilt
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
RATE = 44100
RNG = np.random.default_rng(731908)
DEST = ROOT / 'AzerothCardBinder' / 'Sounds'
PREVIEW = ROOT / 'outputs' / 'sound-preview'
DEST.mkdir(exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)

def tone(freq, seconds, amp=.15, decay=5, bright=.18):
    t = np.arange(round(seconds * RATE)) / RATE
    envelope = (1 - np.exp(-t * 240)) * np.exp(-t * decay)
    # Soft struck-metal overtones, rather than a sustained electronic oscillator.
    signal = np.sin(2*np.pi*freq*t) + bright*np.sin(2*np.pi*freq*2.01*t+.3) + bright*.4*np.sin(2*np.pi*freq*3.97*t)
    return amp * signal * envelope

def paper(seconds=.18, amp=.06, sweep=False):
    n = round(seconds*RATE)
    t = np.arange(n) / RATE
    noise = sosfilt(butter(2, [650, 5600], btype='bandpass', fs=RATE, output='sos'), RNG.standard_normal(n))
    envelope = np.sin(np.pi*np.minimum(t/seconds, 1))**1.7
    if sweep: envelope *= .2 + .8*t/seconds
    return noise * envelope * amp

def cue(seconds, parts):
    result = np.zeros(round(seconds*RATE))
    for start, signal in parts:
        i = round(start*RATE); size = min(len(signal), len(result)-i)
        if size > 0: result[i:i+size] += signal[:size]
    # A very short edge fade prevents clicks. Retain authored relative levels.
    fade = min(440, len(result)//4)
    result[:fade] *= np.linspace(0, 1, fade)
    result[-fade:] *= np.linspace(1, 0, fade)
    return result

def bells(notes, amp=.12, tail=.8, spacing=.09, decay=4.5):
    return [(i*spacing, tone(f, tail, amp, decay)) for i,f in enumerate(notes)]

audio = {
    'paper': cue(.19, [(0, paper(.14,.07)), (.015, tone(190,.13,.035,30,0))]),
    'common': cue(.48, [(0,paper(.11,.035)), (.02,tone(392,.44,.105,9,.10)), (.045,tone(588,.35,.035,11,.08))]),
    'rare': cue(.95, bells([587.33,880,1174.66], .115,.82,.075,5.5)),
    'epic': cue(1.35, [(0,paper(.30,.035,True))]+bells([293.66,440,587.33,739.99,880], .115,1.12,.07,3.8)),
    'legendary': cue(1.95, [(0,tone(146.83,1.8,.14,2.7,.10)),(.04,paper(.5,.055,True))]+bells([293.66,440,587.33,739.99,880,1174.66],.12,1.6,.085,2.8)),
    'shiny': cue(1.65, [(0,paper(.38,.025,True))]+bells([880,1174.66,1479.98,1760,2349.32],.09,1.3,.075,3.3)),
    'pack_anticipate': cue(1.0, [(0,paper(.22,.055)),(.25,paper(.21,.045)),(.5,paper(.35,.055,True)),(.08,tone(146.83,.85,.045,1.7,.06))]),
    'pack_burst': cue(.55, [(0,paper(.17,.15)),(.035,paper(.3,.075,True)),(.01,tone(110,.4,.13,10,.05)),(.08,tone(587.33,.4,.065,8,.08))]),
    'pack_found': cue(.85, [(0,paper(.14,.05))]+bells([440,659.25,880],.105,.70,.08,5.0)),
    'trade': cue(.72, [(0,paper(.08,.055)),(.07,paper(.08,.04)),(.10,tone(293.66,.6,.11,6,.08)),(.14,tone(440,.55,.07,6,.06)),(.17,tone(587.33,.5,.065,6,.08))]),
    'set_complete': cue(1.85, [(0,tone(196,1.6,.115,2.9,.10))]+bells([392,493.88,587.33,783.99,987.77,1174.66],.105,1.4,.10,2.8)),
    'binder': cue(.32, [(0,paper(.24,.05)),(.025,tone(165,.22,.035,16,.03))]),
}
audio['duplicate'] = audio['paper']

timeline, reel, at = [], [], 0
for name, signal in audio.items():
    assert np.max(np.abs(signal)) < .8, name
    sf.write(DEST/(name+'.ogg'), signal, RATE, format='OGG', subtype='VORBIS')
    # Verify the encoded file, not merely the source waveform.
    encoded, rate = sf.read(DEST/(name+'.ogg'))
    assert rate == RATE and np.isfinite(encoded).all() and np.max(np.abs(encoded)) < .95
    timeline.append({'cue': name, 'start': round(at,2), 'seconds': round(len(signal)/RATE,2),
                     'peak': round(float(np.max(np.abs(encoded))),4), 'bytes': (DEST/(name+'.ogg')).stat().st_size})
    reel.extend([signal, np.zeros(round(.45*RATE))]); at += len(signal)/RATE+.45
combined = np.concatenate(reel)
with wave.open(str(PREVIEW/'Warcards-Sound-Preview.wav'), 'wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE)
    f.writeframes((combined*32767).astype('<i2').tobytes())
(PREVIEW/'timeline.json').write_text(json.dumps(timeline,indent=2)+'\n')
print(f'Wrote {len(audio)} original Ogg cues ({sum(x["bytes"] for x in timeline):,} bytes), plus listening reel.')
