# The mixer: your own balance and 5.1 placement (BO-114)

The game mixes every sound itself: who goes to which speaker and how loud is
decided in its code and its data. The mixer sits in the port's audio path,
between the game's voices and the speakers, and sorts the voices into
**buses** (music, the player's engine, impacts, ...). Each bus has a gain,
mute and solo, a route (the game's own panning with trims and field
shaping, six sends of your own, or a place in the 5.1 room), and an LFE
send with a crossover; after the mix there is a trim
and a delay per speaker, an LFE low-pass and a limiter.

Off by default. Off, none of it runs. On with the **Factory** preset the
output is the same as off, bit for bit (see [Neutral is today](#neutral-is-today));
every difference is a setting you changed. Nothing is processed that is not
on the page: no hidden EQ or compression. Two things stand outside it, described
in [custom-music.md](custom-music.md#loudness-bo-132): the loudness of the
player's own music (a setting, with an off) and a peak limiter at -0.5 dBFS in
front of the 16-bit clamp, which does nothing while the mix stays under it.

## Use

Settings overlay (Back+Start, F1, Cmd+,) > **Audio** > **Mixer**. The first
row turns it on (`audio.mixer` in settings.toml, `RECOMP_AUDIO_MIXER=1`).

- **Bus list**: left/right changes the bus gain in 0.5 dB steps, LB/PgUp
  mutes, RB/PgDn solos, Y/Del resets the bus, A/Enter opens it. The bar is
  the bus's level into the mix (RMS over the last 100 ms, -60..0 dBFS).
- **The game keeps running while the Mixer page is open** (the other pages
  pause it): you hear every change as you make it. The game's own controls
  are held meanwhile, so the car coasts; use [Audition](#audition-tuning-on-a-loop-of-your-own-play)
  for steady material.
- **Levels with a pad**: left/right is 0.5 dB a step and speeds up while
  held (2x, 4x, 8x). From "off" a level comes in at -20 dB. A on a send, a
  trim or the LFE send switches it off, or back in at 0 dB (the LFE send:
  -10 dB).
- **A bus**: gain, mute, solo, route, then what the route offers (field
  width, divergence and the four trims; the six sends; or the position,
  width and divergence of pan mode), the LFE send and its crossover.
- **Pan mode** shows the room from above beside the rows: the five speakers
  on its edge (each dot grows with what the speaker gets, the number is dB
  under the sound's level), the listener in the middle, the sound's position
  and, with a width, its two ends L and R. A on "Position", then the D-pad
  or the stick moves it (0.05 a step; A or B when done); or drag in the
  diagram with the mouse. X, Y, width and divergence are rows too.
- **Master rows**: limiter, ceiling, LFE low-pass, mains high-pass, the
  speakers' trims and delays, the ducking slot.
- **Meters** at the bottom: each speaker feed after the output stage, RMS
  bar and peak-hold tick (1.5 s), the peak in dBFS, a red block and the
  count of samples past full scale (what the hard clamp, or nothing if the
  limiter is on, cut), the limiter's and the ducking's gain reduction.
- **A and B**: A is your mix, kept in `mixer.toml`. B is a reference held in
  memory (Factory unless you pick another preset on the "B is" row). **F7**
  or **Back + Y** switches what you hear, with the overlay open or closed.
  Edits made while B is heard change B only.
- **Presets**: "Load a preset into A" offers the built-in ones and every
  `mixer-<name>.toml` beside `mixer.toml`; "Save a copy of A" writes
  `mixer-1.toml` (the next free number), to rename as you like.

`mixer.toml` is beside `settings.toml` (macOS: `~/Library/Application
Support/Burnout3/`, Linux and the Deck: `~/.local/share/burnout3/`,
Windows: `%APPDATA%\Burnout3\`); `RECOMP_AUDIO_MIXER_FILE=<path>` names
another. It is written when the mixer is first turned on, rewritten 0.4 s
after a change in the overlay, and **read again within a second whenever it
changes on disk**: edit it in a text editor while the game runs and listen.
The log says `[APU] mixer: <file> loaded`, with the first unknown key or
bus if there is one; a file with a syntax error is not applied and the
running mix stays.

## Signal flow

```
 game voice (mono or stereo, the game's envelope and its eight sends:
   |         mixbin + volume each)
   |
   |  bus = classification (below)
   v
 [bus gain] x [mute / solo] x [ducking, if the bus is the duck target]
   |
   +-- route "title": the game's own sends
   |        -> field width (its FL/FR and its SL/SR pair, around the
   |           centre line) -> field divergence (its C against FL/FR)
   |        -> x the trim of each send's speaker group
   |           (front / centre / LFE / rear)                    ---> mixbins
   |           (width 1, divergence 0 and trims 0 dB: none of this runs)
   |
   +-- route "sends": FL FR C LFE SL SR sends x the voice's level
   |                  (level = its loudest send in the game's mix;
   |                   L channel -> FL, SL; R -> FR, SR; (L+R)/2 -> C, LFE)
   |                                                    ---> speaker mixbins
   |
   +-- route "pan":   a place in the room x the voice's level: each channel
   |                  through the pan law's five gains (FL FR C SL SR);
   |                  nothing to the LFE                ---> speaker mixbins
   |
   +-- LFE send (optional): (L+R)/2 x level x send
                  -> per-bus sum -> low-pass (the crossover)  ---> LFE mixbin

 32 mixbins --(the game's own send EQs and speaker map, as before)--> six
 speaker feeds FL FR C LFE SL SR   (stereo output: the left/right fold)
   |
   v
 output stage:  LFE low-pass -> mains high-pass -> speaker trim
                -> speaker delay -> soft clip | peak limiter
   |
   v
 safety peak limiter (-0.5 dBFS, acts only when the mix reaches it)
   |
   v
 clamp to full scale, 16 bit -> device (the overlay's master volume after it)
```

Stereo output: the same buses and gains. A "sends" route is folded as ITU
does: L = FL + 0.707 C + 0.707 SL, R likewise, the LFE send dropped. A
"pan" route uses x only (y and divergence do nothing), constant power
between left and right. Field width acts on the left/right pair, field
divergence has no centre to work with. The
game sends everything to the left/right pair in stereo, so of the four
trims only the front one applies, and of the speaker rows only front
left/right.

## Controls

| Control | Range | What it does |
|---|---|---|
| Bus gain | off, -60..+12 dB | The whole bus. |
| Mute / Solo | | With any solo on, only soloed buses sound. |
| Route | game's panning / sends / a place in the room | See the flow above. |
| Field width | 0..2 | Route "game's panning": each sound's FL/FR pair and SL/SR pair narrower or wider around the centre line. 1 as the game pans, 0 both speakers of a pair equal, 2 wider (a sound that leans left leans further). The sound's power is kept; its sends stay on the game's own bins and polarities. |
| Centre divergence (field) | -1..+1 | Route "game's panning": above 0 that share of the power the game sends to the centre goes to FL and FR, half each; below 0 that share of the power FL and FR have in common goes to the centre. Power kept. |
| Position X, Y | -1..+1 | Route "a place in the room": see [The pan law](#the-pan-law). |
| Width (pan) | 0..1 | The two channels of a stereo sound sit at x - width and x + width (clamped to the walls): 1 at the front is left on FL and right on FR; 0 puts both at the position. A mono sound is at both places with half its power each. |
| Centre divergence (pan) | 0..1 | That share of the centre speaker's power goes to FL and FR, half each: 1 is a phantom centre. |
| Front / Centre / Rear / LFE trim | off, -60..+12 dB | Route "game's panning": the game's send to that speaker group, scaled. The sound keeps moving as the game pans it. |
| Send to FL FR C SL SR, LFE | off, -60..+12 dB | Route "sends": 0 dB is the sound's own level. The sound no longer moves; for music, engine, exhaust, UI. Six independent levels: power is whatever you set. |
| LFE send | off, -40..+12 dB | An extra feed of the bus to the LFE, on top of the route. |
| LFE send crossover | full range, 60..150 Hz | Butterworth low-pass, 4th order (24 dB/oct, -3 dB at the frequency) on that send. |
| Limiter | off / soft clip / peak | Off: the hard clamp at full scale, as shipped. Soft clip: linear to 3 dB under the ceiling, a tanh knee above; no delay. Peak: look-ahead limiter, 64 samples (1.33 ms, which it adds to the output latency), all channels linked, release as set; what its attack lets through is clamped at the ceiling. |
| Ceiling | -12..0 dBFS | For the soft clip and the limiter. Default -0.3. |
| Limiter release | ms (file only) | Default 200. |
| LFE low-pass | off, 60..150 Hz | 4th-order Butterworth on the LFE feed. The console's Dolby Digital encoder band-limited the LFE at 120 Hz; the game's own LFE feed is full range (45 % of its energy above 120 Hz in a race). |
| Mains high-pass | off, 60..150 Hz | 4th-order Butterworth on the five mains, all buses (not per bus). |
| Speaker trim | -24..+12 dB | After the mix, before the limiter. |
| Speaker delay | 0..50 ms, 0.5 ms steps | 1 ms = 48 samples = 34 cm. |
| Ducking | one slot | While the source bus is above the threshold (dBFS RMS over a 0.67 ms frame, after the source's own gain), the target bus goes down by the depth; attack and release are time constants. The game already ducks music 7.9 dB under the DJ itself. |

## The preset file

TOML, every key optional (what is missing is neutral). Levels in dB, `"off"`
is silence, times in ms, frequencies in Hz.

```toml
[master]
limiter = "off"            # off | soft | peak
ceiling_db = -0.3
limiter_release_ms = 200
lfe_lowpass_hz = 0         # 0 = off
mains_highpass_hz = 0

[speaker.SL]               # FL FR C LFE SL SR
trim_db = 0.0
delay_ms = 0.0

[duck]
enabled = false
source = "impacts_crash"
target = "music"
threshold_db = -30.0
depth_db = 6.0
attack_ms = 20
release_ms = 400

[bus.music]
gain_db = 0.0
mute = false
solo = false
route = "title"            # title | sends | pan
field_width = 1.0          # route title: 0..2
field_divergence = 0.0     #              -1..1
front_db = 0.0
centre_db = 0.0
lfe_db = 0.0
rear_db = 0.0
send_fl_db = 0.0           # route sends
send_fr_db = 0.0
send_c_db = "off"
send_lfe_db = "off"
send_sl_db = "off"
send_sr_db = "off"
pan_x = 0.0                # route pan: -1 left .. +1 right
pan_y = 1.0                #            -1 rear .. +1 front
pan_width = 1.0            #            0..1
pan_divergence = 0.0       #            0..1
lfe_send_db = "off"
lfe_crossover_hz = 80
```

Bus keys: `music`, `dj`, `film`, `streams`, `player_engine`,
`player_exhaust`, `other_cars`, `traffic`, `tyres_road_wind`,
`impacts_crash`, `boost`, `ui_hud`, `other`.

### Built-in presets

| Preset | What it changes, and why |
|---|---|
| **Factory** | Nothing. |
| **Music front** | Music: route pan, x 0, y 1, width 1, divergence 0: the left channel on FL, the right on FR, nothing in the centre, the rears or the LFE. (Narrow the width to bring the centre speaker in: at 0.5 each channel is between C and its side.) The game plays music on all four corners with the rears only 1.6 dB under the fronts, plus a full-range copy on the LFE at -17 dB, which covers the surround field the effects use. |
| **Engine centred** | Player engine: route pan, x 0, y 1 (front centre), width 0.25: C at -1.1 dB, FL and FR at -9.6 dB. Player exhaust: route pan, x 0, y -0.3 (a little behind the listener), width 0.5: SL and SR at -4.7 dB, FL and FR at -9.4 dB, C at -10 dB. Both an LFE send of -9 dB under 80 Hz. In the game's own 5.1 mix the engine and the exhaust are both centred on FL and FR (-9.4 dB each), with the LFE at -6 dB and the centre and rears 13 dB under the fronts (docs/audio-gp.md). |
| **Crash weight** | Impacts: LFE send -6 dB under 80 Hz; LFE low-pass 120 Hz; music ducked 4 dB under impacts (threshold -30 dBFS, 20 / 400 ms); peak limiter at -1 dBFS. The crash run-up reaches +5.7 dBFS before the clamp (2559 samples over in 25 s) and its LFE is fed by the crash streams and a few impact waves only. |

They are starting points from the measurements of the game's mix (BO-114's
study: `tools/mix`, `runs` in its notes), not tuned by ear.

## The pan law

Route "pan" places a bus in a plane seen from above: a square room with
the listener in the middle, x from -1 (left wall) to +1 (right wall), y
from -1 (rear wall) to +1 (front wall). The speakers are on its edge: C at
(0, 1), FL (-1, 1), FR (1, 1), SL (-1, -1), SR (1, -1). The corners stand
for the angles ITU-R BS.775 gives the speakers (C 0, FL/FR +-30, SL/SR
+-110 degrees): the room is the usual surround-panner picture, not a
drawing of the living room to scale.

- **On the edge**, a point is played by the two speakers next to it on the
  ring FL - C - FR - SR - SL (and back to FL), with the constant-power
  sine/cosine law: at the share t of the way from speaker A to speaker B
  (by angle as seen from the middle), gain A = cos(t x 90 deg), gain B =
  sin(t x 90 deg). Exactly on a speaker, only that speaker plays. Halfway
  along the rear wall: SL and SR at -3 dB; halfway along a side wall: the
  front and the surround of that side at -3 dB.
- **Inside**, at distance r = max(|x|, |y|) from the middle, each speaker's
  power is (1 - r) / 5 + r x its power for the point on the edge in the same
  direction. In the middle (r = 0) all five play equally, at -7 dB each.
- **Divergence** d moves the share d of the centre speaker's power to FL and
  FR, half each.
- **Width** w: a stereo sound's left channel is panned as the point
  (x - w, y), its right channel as (x + w, y), each with its own five gains.
  A mono sound gets, per speaker, the root of the mean of those two points'
  powers.
- The squares of a channel's five gains always sum to 1: a sound's power
  does not change with position, divergence, or (for a mono sound) width.
  For a stereo sound the two channels' powers add as long as they differ;
  what they have in common adds in level where both feed one speaker, as
  with any narrowing of a stereo signal (up to +3 dB at width 0 for a
  sound that is the same in both channels).
- The LFE gets nothing from the panner: use the bus's LFE send.
- Level: the sound's own, i.e. its loudest send in the game's mix (which
  carries the game's volume sliders and its own fades).
- **Stereo output**: x only; left gain cos((x + 1) x 45 deg), right gain
  sin((x + 1) x 45 deg) per channel. At x 0 and width 1 the left channel is
  on L only and the right on R only, as shipped, and the mono sum of the
  output is the mono sum of the source.

Field shaping (route "title") does not re-pan from an estimated direction:
it works on each sound's own send levels. Width: with l and r the levels
of a pair, m = l + r and s = (l - r) x width (limited to +-m), the new pair
is (m + s)/2 and (m - s)/2, scaled so that l^2 + r^2 is unchanged.

## How a sound finds its bus

| Bus | What is in it | How it is recognised |
|---|---|---|
| Music | EA GAMES TRAX and custom music (BO-108: your own folder) | a stream voice turned on by the music manager: its EA GAMES TRAX player, its custom-soundtrack player (another stream, started elsewhere in it), or any other place in its code but the DJ's |
| DJ | the DJ's speech; the radio idents | a stream turned on by the music manager's speech path; the `ident` waves |
| Film | the intro, the training films | a stream turned on by the film player |
| Streams | RenderWare's streams: crash sweeteners, ambience, the menu's bed | a stereo buffer voice turned on by RenderWare's stream player |
| Player engine | the engine layers of your car (`eng_<rpm>`, ...) after the game's distortion, as the game places them | the game's return voice of mixbin 17 (docs/audio-gp.md). The layers themselves, which only feed the distortion, are in no bus |
| Player exhaust | its exhaust layers (`ex_<rpm>`, ...), likewise | the return voice of mixbin 18 |
| Other cars | rivals' engines and exhausts; gear changes, turbo, dump valve | a car's wave on the positioned routing |
| Traffic | traffic engines, horns, pass-bys, air brakes; trams, trains, planes | by wave name |
| Tyres/road/wind | road surface, tyre noise and skids, wind | by wave name |
| Impacts/crash | impacts, scrapes, glass, parts, explosions, fire, steam, alarms, props, kerbs | the crash dictionaries; props of a track |
| Boost | boost in / loop / out, the flash | by wave name |
| UI/HUD | menus, the event's HUD sounds, countdown | the front-end dictionary and the events' |
| Other | whatever was not recognised | |

The game plays its samples through RenderWare Audio; each is a named wave
in a wave dictionary on the disc (`sound/*.awd`, each track's `sound.awd`,
each car's `.hwd` and `.lwd`: 1575 waves in 174 files). It starts its voices
from one update tick, so the code that starts a voice says nothing about
the sound; the wave does. When the mixer is turned on, the port reads the
dictionaries of **your own disc** once, on a thread (no list of the game's
data is shipped; the rules in `core/mixer.c` only say which file and
name go to which bus), keeps each wave's first 16 bytes and 16 more at
+0x400 / +0x440, and recognises a voice by the bytes of its buffer when it
starts. Streams have no wave; the guest return addresses on the stack at
the turn-on say which player started them.

What lands where it should not, or cannot be separated:

- **Other** should stay silent: in a traced race every sounding voice had a
  named bus. If a sound is missing from its bus, solo "Other". A wave that
  begins with more than 1 KB of digital silence and is shorter than that
  cannot be told from another such wave and is left in Other.
- Gear changes, turbo and dump-valve sounds are in **Other cars**: the
  game plays the player's and the rivals' the same way.
- `crashescap` and the player's stuck horn (`p1horn`) are filed under
  Impacts/crash, `bstps*` under Traffic: by their names, not verified by ear.
- A stream that was already playing when the mixer was turned on is taken
  for Music until it next starts (films, the DJ: a few seconds).
- What is mixed into one wave or one stream stays together: a crash
  sweetener stream cannot be split into its metal and its glass, a music
  track not into its instruments.
- The reverb send (the game's mixbin 11, the overlay's "Surround effects
  level") follows its bus's gain and front trim; it has no control of its
  own here. With route "sends" a bus sends nothing to the reverb.

## Neutral is today

The audio rule of this port: no change to the sound without proof.

- **Off**: `apu_vp.c`'s mix loop and `apu_dsp.c`'s conversion run as they
  were; the mixer is one branch a voice and one a frame.
- **On, neutral**: mixing is linear, but floating-point sums depend on
  their order, so a neutral mixer is bit-identical only if it performs the
  same operations in the same order. It does: with a bus at 0 dB, route
  "title", trims at 0 dB and no LFE send, the voice's gain is not multiplied
  at all and goes into the same single accumulator per mixbin; with no
  output processing the speaker feeds are the same sums, clamped and
  converted the same way.
- Pan mode and the field shaping are other branches: a bus on route
  "title" with field width 1 and divergence 0 takes the plain loop, whatever
  its pan settings say (tested: such a bus is byte-identical).
- "Off" and "Factory" are the game's own mix as the console's effects
  stage makes it (docs/audio-gp.md): the sends with the game's gains and
  signs, the player's engine through the distortion and the return voices.
  The mixer sits on both sides of that stage: the buses before it (a
  sound's level into the mixbins), the output stage after it. The engine
  layers that only feed the distortion are in no bus, so a bus control
  never changes how hard the distortion is driven; the engine and exhaust
  buses hold what comes back from it.
- **Proof 1** (the toolkit's `tests/apu_bus`, in the test suite): 600 frames
  of 24 voices on the game's real bin sets; the mixbins against the VP's own
  loop and the DSP stage's 16-bit output (the effects image wired as the
  game's) with the mixer off against on, stereo and 5.1: 0 bytes differ,
  with 44 000 clamped samples in the set and a control (0.1 dB on every bus
  is seen).
- **Proof 2** (`apu_bus_replay`, on a recording): 10 s of a race recorded in
  the game with the mixer off (`RECOMP_MIX_TRACE_REC`: every voice's samples
  and gains, the return voices among them, and the mixbins the game
  produced; 15 000 frames, 702 358 voice frames). Replayed: the loop
  reproduces the game's own mixbins in every frame; the neutral mixer's
  mixbins equal them in every frame; the 16-bit output is identical, stereo
  and 5.1.

Two runs of the game itself are never sample-identical (BO-108 measured
it), which is why the proof is a replay of recorded inputs and not two
captures.

## Cost

On the Mac this was built on (Apple silicon), the recorded race (45 voices
a frame), per 32-sample frame: the game's loop alone 2.8-3.4 us, with the
neutral mixer 6.3-9.5 us, with every control on every bus on (a third of
the buses on sends, a third in pan mode, a third on the game's panning with
field shaping; LFE sends with crossovers, both output filters, delays,
ducking, the peak limiter) 10.7-13.1 us. At 1500 frames a second that is 0.4-0.5 % of a core
as shipped, about 1-1.4 % with the mixer neutral, 1.7-2 % with everything
on. It runs on the APU's frame thread, not on the game's. Expect two to
three times these figures on a Steam Deck (not measured there yet). Reading
the dictionaries when the mixer is turned on: 174 file headers, on its own
thread.

## Checking it

- Toolkit: `OVERLAY_SHOT_MIXER_E2E=<file> overlay_shot <prefix>`: every
  control of every view of the page worked with pad buttons, each followed
  by the mixer's active configuration and the levels it renders; the
  audition rows; which views pause the game.
- Toolkit: `tests/apu_bus` (identity, each control, the preset file; the
  pan law's power over a 21 x 21 grid of positions and five divergences,
  its named places, route pan through the mixer for mono and stereo sounds
  on a 5.1 and a stereo output over positions and widths, field width and
  divergence over a grid of pans),
  `apu_bus_replay <recording>`, `tests/overlay_settings`, and
  `OVERLAY_SHOT_MIXER=<file> overlay_shot <prefix>` (the page driven off
  screen, with checks).
- Game: `tests/mixer` (`bo3_mixer_test`: the name rules, a wave table from
  dictionaries made by the test, voices and streams, the presets).
- `tools/mix`: the traced scenes and the per-bus report of the study;
  with the mixer on the trace adds an `M` line a second with each bus's
  level and voices.

## Audition: tuning on a loop of your own play

A mix is hard to judge on sound that keeps changing. The Mixer page can
loop a stretch of the game's sound that you recorded while playing, and
play it through the mixer in place of the live sound, so every change is
heard on the same material each time round.

- **Audition recording**: Off (the default) / The last 30 s / The last 60 s.
  While it is on, the mixer keeps what it mixed: for every 32-sample frame,
  each sounding voice's samples as 16 bit, its mixbins, gains and bus. The
  store takes 3 MB a second kept (90 MB for 30 s, 180 MB for 60 s); a race
  filled it at about 2 MB a second (59 MB for a 30 s clip). Off, nothing is
  recorded and no memory is held.
- Play: a race, a crash, boost, traffic. Then **Audition**, A: the last 30
  (or 60) seconds loop. The clip's voices go through the mix loop again
  frame for frame, so the buses, mute and solo, routes (pan mode too),
  sends, LFE sends, ducking, the limiter and the meters act on it exactly as
  on live sound. The game runs on underneath, unheard (or pause it first
  from another page: the loop does not need it). A again: the live sound is
  back and the recording starts afresh.
- The loop point is cross-faded over 2 s, equal power, so the loop is 2 s
  shorter than what was recorded. The row shows the position.
- **Save this clip** (while it loops) writes `mixer-audition.clip` beside
  `mixer.toml`; right on the Audition row loops that saved clip, also after
  a restart. It is your own recording of the game: it stays on your
  machine, and is not part of any release or of this repository.
- A and B, and every control, work on the loop as on live sound.
- With the neutral preset the loop's sum is the live sum to the samples'
  16-bit quantisation (the largest difference in the test: -102 dB).
  Recording only copies: with it on, the neutral mixer's output is still
  bit-identical (the identity test runs that way).
- Not in the clip: sounds the mixer does not carry as bus voices (the raw
  feeders of the engine's effect; their result, the Player engine and
  exhaust buses, is).

## Not done

- A bus for the reverb: it is part of the mix the mixer starts from
  (docs/audio-gp.md) and follows the engine and exhaust buses' sends, but
  has no control of its own.
- No per-bus EQ, no per-bus high-pass, one ducking slot.
- LUFS metering.
