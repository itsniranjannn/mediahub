import wave, struct, math, os, random, sys
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

def info_chunk(tags):
    body = b'INFO'
    for k, v in tags.items():
        b = v.encode('utf-8') + b'\x00'
        if len(b) % 2: b += b'\x00'
        body += k.encode() + struct.pack('<I', len(b)) + b
    return b'LIST' + struct.pack('<I', len(body)) + body

def tone(path, freq, secs, rate=44100, ch=2, tags=None, amp=0.25):
    n = int(rate * secs)
    frames = bytearray()
    for i in range(n):
        v = int(32767 * amp * math.sin(2 * math.pi * freq * i / rate))
        frames += struct.pack('<h', v) * ch
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(bytes(frames))
    if tags:
        with open(path, 'r+b') as f:
            data = f.read()
            chunk = info_chunk(tags)
            data += chunk
            data = data[:4] + struct.pack('<I', len(data) - 8) + data[8:]
            f.seek(0); f.write(data); f.truncate()

tone(f'{out}/Audit_Tone_A4_stereo_10s.wav', 440, 10, tags={'INAM': 'Audit Tone A4', 'IART': 'Audit Artist One', 'IPRD': 'Audit Album Alpha'})
tone(f'{out}/Audit_Tone_B4_mono_30s.wav', 493.88, 30, rate=22050, ch=1, tags={'INAM': 'Audit Tone B4', 'IART': 'Audit Artist One', 'IPRD': 'Audit Album Alpha'})
tone(f'{out}/Audit_Tone_C5_stereo_5s.wav', 523.25, 5, tags={'INAM': 'Audit Tone C5', 'IART': 'Audit Artist Two', 'IPRD': 'Audit Album Beta'})
tone(f'{out}/Audit_Long_Tone_5min.wav', 220, 300, rate=8000, ch=1, tags={'INAM': 'Audit Long 5min', 'IART': 'Audit Artist Two', 'IPRD': 'Audit Album Beta'})
tone(f'{out}/गीत_नेपाली_audit.wav', 330, 8, tags={'INAM': 'गीत नेपाली', 'IART': 'कलाकार', 'IPRD': 'एल्बम'})
tone(f'{out}/Ünïcödé — ♪ track [audit].wav', 392, 8)
tone(f'{out}/audit_no_tags.wav', 300, 6)
# broken / odd files
open(f'{out}/audit_zero_byte.mp3', 'wb').close()
random.seed(7)
open(f'{out}/audit_corrupt_random.mp3', 'wb').write(bytes(random.getrandbits(8) for _ in range(40000)))
open(f'{out}/audit_fake_video_random.mp4', 'wb').write(bytes(random.getrandbits(8) for _ in range(60000)))
import shutil
shutil.copy(f'{out}/audit_no_tags.wav', f'{out}/audit_wav_named_mp3.mp3')
shutil.copy(f'{out}/audit_no_tags.wav', f'{out}/audit_noextension')
for f in sorted(os.listdir(out)):
    print(f, os.path.getsize(os.path.join(out, f)))
