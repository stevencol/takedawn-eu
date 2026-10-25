# The game's effects stage (GP image)

On the console the audio chip's Global Processor, a DSP, runs the effects
image the game ships (`sound/DSP/B3XboxFx.bin`). It takes the 32 mixbins the
voices were summed into and makes the six speaker feeds. The port does not
run a DSP: the toolkit has a model of what this image does
(`src/apu/apu_gp.c`), and `core/gp_image.c` tells it which effect sits
on which mixbin. This page is what that stage does and how it was checked.

It is the same in 5.1 and in stereo; in stereo the six feeds are folded to
two at the end.

## Which mixbin reaches which speaker

| Mixbin | Reaches | Gain | What the game sends there |
|---|---|---|---|
| 0..5 | FL FR C LFE SL SR | 1 | music, films, speech, the front end (streams) |
| 19 20 21 22 23 | FL FR SL SR C | +1 | positioned sounds: other cars, traffic, tyres, impacts |
| 25 13 14 15 16 | FL FR SL SR C | -1 (inverted) | the same sounds; the game picks this set or the one above for each of a sound's six sends |
| 24 | LFE | 0.5 | the LFE send of positioned sounds |
| 17, 18 | no speaker | | the player's engine and exhaust layers: see below |
| 11 | no speaker (dry) | | the reverb's input; wet to FL FR SL SR (below) |
| 6..9 | FL FR SL SR | 1 | never used by the game (the console adds a low shelf and a cross feed: not modelled) |
| 10, 12, 26..31 | no speaker | | never used by the game |

The gains of the eleven sends are not fixed in the image: each passes a
two-pole filter whose first coefficient the game sets (+1, -1; the LFE one
stays at the image's default, a flat one half), and the model reads them as
the game sets them. LFE: after this stage the console's Dolby Digital
encoder band-limited the LFE channel; the port low-passes the LFE feed at
120 Hz (24 dB an octave) in its place, always: that is the stock mix. (A
developer setting can move it, `audio.lfe_lowpass` in settings.toml or
`RECOMP_AUDIO_LFE_LOWPASS`: off, 80, 100, 120; there is no menu row.) It
matters: the engine's
LFE send is full-range, so in a race the LFE feed is -23.7 dBFS RMS with
the filter off and -33.3 / -34.0 / -34.9 dBFS at 120 / 100 / 80 Hz. The
mixer's own LFE low-pass (its master section) is the control for tuning
by ear; it comes after this one, and with both on the feed passes both.

## The player's engine

The engine and exhaust layers of your car do not go to a speaker. The game
sends them to mixbins 17 and 18, where the image runs a distortion in place:
the signal times eight, clipped hard at full scale (that is the bite of the
engine under load; from -18 dBFS in, it clips), plus, on the engine, a
small component from a wave folder and a resonant low-pass whose level
(1 to 8 % of full scale), drive and gain the game moves with throttle and
revs. Every 32 samples the DSP program copies mixbins 11..30, as they are
after the effects, into memory the game can reach. Two looping voices of
the game (hardware voices 68 and 69) have their 32-sample buffers exactly
on the copies of mixbins 17 and 18 and play them back, one 32-sample frame
later, to FL and FR (about -9.4 dB each in a race), the LFE send (-6 dB),
centre and rears (about -22.5 dB) and the reverb's input (-6 dB). The game
moves those volumes (they fade with the camera and in a crash).

So the engine is centred between the front speakers with weight on the LFE,
and it is about 18 dB of distortion gain louder into those voices than the
layers themselves.

## The reverb

Mixbin 11 feeds the image's I3DL2 reverb: early reflections and a feedback
network of four delay lines, wet only, to FL FR SL SR. The game sends it
the engine's return voices (-6 dB) and sets one preset for the whole game,
a large hangar (decay time 10 s, reflections after 20 ms, the late part
after 30 ms), of which it moves only the room level: shut in the front
end, -50 dB in a race in the open, -25 dB while the road surface under
your car is marked as covered (tunnels, underpasses, car parks; the mark
is in the track's collision data). The level slides over about 0.15 s.
Silver Lake has three covered stretches in its first two minutes;
Waterfront one short underpass; Downtown none.

The port does not restate the reverb by hand: its 1211 words of DSP code
run through a small interpreter of the DSP's instruction set
(`src/apu/apu_dsp56k.c` in the toolkit), with its delay lines where the
image keeps them, in the DSP's scratch memory. The handful of inner loops
it spends its time in have native versions, each proven to give the same
memory and registers as the interpreted code.

Its level in the mix (a race on Silver Lake, RMS per speaker): about
-61 dBFS in the open, about -35 dBFS under cover, where the fronts are at
-19 and the surrounds at -24. The tail decays 6 to 7 dB a second.

A fault this uncovered: DirectSound reads the reverb's delay table back
from the DSP's memory before it converts a new setting. The port's DSP
memory window was empty, so every setting came out with the four decay
filters silent: the reverb had early reflections only, on every track,
until the model's state was made visible there.

## What is exact and what is not

- The distortion is the image's own arithmetic, word for word (the DSP's
  56-bit accumulators, its truncating multiplies and its limiting), with its
  parameters taken over at the moments the game's commands hand them to the
  DSP. Checked against a reference of the stage (below): the copies of
  mixbins 17 and 18 are identical on every sample of a 165 s race capture
  and a 223 s crash capture.
- Sends, gains, signs: identical within 3 steps of 24 bits on every speaker
  once the reference's reverb is taken out.
- The reverb is the image's own program, run instruction by instruction
  (below): identical to the reference on every sample of its eight test
  renders.
- The LFE low-pass is the port's own, after what AC-3 does; the encoder
  was not measured. Nothing was compared with a real console.
- The stereo fold (FL + 0.707 C + 0.707 SL, no LFE) is the usual one; what
  the console's stereo output did was not measured. In stereo mode the game
  itself sends the engine's return voices to mixbins 0 and 1.

## How it was checked

A reference tool (separate, not part of this project) runs the game's own
DSP image on captured mixbins. The capture is the port's own: every frame's
mixbins, the game's parameter writes and commands, the return voices'
volumes. `tests/gp/bo3_gp_replay` plays the same capture through the model
and `tools/mix/gp_compare.py` compares the six-speaker renders:

| | level difference | correlation | residual |
|---|---|---|---|
| race, FL FR | 0.00 dB | 1.00000 | -62 dB (the reverb) |
| race, C LFE | 0.00 dB | 1.00000 | -109, -111 dB |
| race, SL SR | 0.00 dB | 0.99997, 0.99999 | -43, -46 dB (the reverb) |
| crash, FL FR | 0.00 dB | 1.00000 | -68, -66 dB |
| crash, C LFE | 0.00 dB | 1.00000 | -109, -101 dB |
| crash, SL SR | 0.00 dB | 0.99999, 1.00000 | -49, -52 dB |

Unit tests: the toolkit's `tests/apu_gp` (routing, polarity, commands, the
copy and its one-frame timing, the distortion against measured impulse
responses, the LFE filter) and `tests/gp` here (this image's table). In the
running game the return voices were checked from a recording of the mix
loop: voice 69's samples are eight times mixbin 18 of the frame before,
clipped, on every sample.

Cost: 8 to 17 microseconds a 32-sample frame on an M-series Mac (1.2 to
2.5 % of a core), nearly all of it the reverb.
