# Custom music: your own folder in EA GAMES TRAX (BO-108)

Burnout 3 on the Xbox plays custom soundtracks: music ripped on the dashboard
shows up in Driver Details > Settings > EA GAMES TRAX, where X ("NEXT
SOUNDTRACK") steps from EA GAMES TRAX through the console's soundtracks. The
port offers a folder of your own music there. Off by default.

## Use

In the game: the settings overlay (Back+Start, F1, Cmd+,), Audio page,
**Custom music folder**. A opens a folder list inside the overlay; a pad is
enough (D-pad, A to open or choose, B to go back):

- it starts on the places: the folder in use, the folder it is in (one step
  up to a folder of soundtracks), Music, Home, Downloads and what
  is mounted (macOS: /Volumes; Linux and the Steam Deck: /run/media, the SD
  card among them, /media, /mnt; Windows: the drive letters), and "Computer: /";
- in a folder: "Use this folder", "..", and its folders, each with the number
  of songs in it as the game reads it (three levels down)
  (counted in the background, up to 20 000 entries a row: "1234+ songs" when
  it stopped there);
- "Turn custom music off" on the places, when a folder is set;
- in the folder in use the cursor starts on "..", and ".." (or B) from it, or
  from the folder it is in, goes on up the disk instead of back to the places
  (BO-243).

The choice is saved as `audio.custom_music_dir` in settings.toml and used at
once: the line under the row counts the files while the folder is read, then
says how many soundtracks there are. Then, in the game: Driver Details >
Settings > EA GAMES TRAX, X until the folder's name is the heading, A to
confirm. In a race the Black button skips to the next song, as with EA GAMES
TRAX; Y in the screen switches random order. The original does not remember
the choice: it starts on EA GAMES TRAX every run (see "Custom music at
start" below for what the port does about that).

## Custom music at start (BO-230)

With a folder set, the game starts on the custom soundtrack you last chose in
Driver Details > Settings > EA GAMES TRAX, with no visit to that screen. The
Audio page has the row **Custom music at start** under "Custom music folder"
(`audio.custom_music_at_start`, on by default; greyed out while no folder is
set; the row's hint says why).

- The soundtrack you confirm in the game's screen (A) is remembered by name in
  settings.toml as `audio.custom_music_soundtrack`. Confirming EA GAMES TRAX
  remembers that: the key is then `""` and nothing is switched at start.
  With no key (nothing chosen yet) the first soundtrack is used. A name the
  folder no longer has gives the first soundtrack. The name is the
  soundtrack's as the title lists it (cut at 31 characters, Latin-1).
- At start, when the title's music manager has counted the folder's
  soundtracks (the log's "the title now counts N soundtracks"), the title's
  first music start is put on that soundtrack, once per run: the port sets
  the title's chosen source, as the screen's confirm does, and the title's
  own code starts the track. The EA GAMES TRAX screen, the Black-button skip
  and random order work as they did. A choice made in the screen before that
  point wins and is remembered. A folder chosen in the overlay while the game
  runs is not switched to: that is not a start.
- Off (`audio.custom_music_at_start = false`) or no folder: the title starts
  on EA GAMES TRAX, as before.

Whether the title remembers the choice (checked in its code, BO-230): it does
not. The boot code clears the manager's chosen source (+0x568) to 0, EA GAMES
TRAX (`sub_00153B00`, 0x153B55). The screen keeps its own candidate (X steps
it, wrapping to 0), and A copies it to the manager (`sub_00084260`, 0x842A9:
`[0x411B50] = candidate`) and stores the random-order byte (0x4AE1DA) and the
EA GAMES TRAX per-track flags (0x4AE1A0..) in the profile. Nothing reads the
source back but `sub_00155420`, the title's start of the music of the source
chosen, which runs when the screen is left and at each music start.

While one of the folder's soundtracks is the game's music (always so after
custom music at start), a new folder is read at once and held back until the
game runs again: the row says so while the overlay is open. Then, with a song
of the old folder playing, the title's soundtrack becomes the new folder's one
of the same name, else its first, the song playing goes on to its end, and the
next song and the EA GAMES TRAX screen are the new folder's. With no song
playing it happens at the title's next music start, the same way. A new
folder with no music turns custom music off at the next music start. The
switch is not a choice in the game's screen, so audio.custom_music_soundtrack
stays as it was (BO-243; before it, the change waited for a restart, and with
custom music at start on that was every change).

Also: `--music-dir <folder>` for one run, or `RECOMP_AUDIO_MUSIC_DIR` (the
row is then locked), or the key in settings.toml by hand:

```toml
[audio]
custom_music_dir = "/Users/you/Music/Driving"
```

- A folder of songs, or a folder of folders: each one a soundtrack. The
  folder's own files are one soundtrack, and each folder directly in it is
  another, named after the folder, with the songs in its own folders two
  levels further down counted in (an artist's folder with album and disc
  folders is one soundtrack; the albums are not soundtracks of their own).
  100 soundtracks, 500 songs each; the rest is left out and the log says how
  many. Deeper than that is not read, and a folder that is a link is not
  followed. The folder is read in the background, at start too (the game
  never waits for it), and at most 20 000 entries of it: choosing Home or a
  whole disk stops there and the row says so.
- mp3, flac, ogg (Vorbis) and wav play everywhere. On macOS also m4a (AAC and
  Apple Lossless, what an Apple Music or iTunes library holds), aiff and caf,
  through the system's own decoder; protected files (m4p) do not. Opus and
  WMA files do not play.
- A file that cannot be read is left out, and said: the line under the row
  counts what was left out, the lines below it name the files with the
  reason, and the log has every one (`[SOUNDTRACK] left out: <file>:
  <reason>`).
- Songs are listed in natural order of file name and named by their title
  tag, else the file name. Names are cut at 31 characters and kept to
  Latin-1, as far as the title's font goes: "ő" shows as "ö".
- At start the folder is read before the title boots (10 000 small files:
  0.3 s on the Mac it was measured on).

## Loudness (BO-132)

Modern songs are mastered at about -7.5 LUFS with peaks at or past 0 dBFS.
The title sends a custom-soundtrack stream about 8 dB hotter than its own
EA GAMES TRAX streams, and in stereo the fold sums the fronts, the centre
and the surrounds on top, so the mix reached past full scale and the 16-bit
clamp cut it flat: distortion. Two things stand in front of that.

- **Custom music loudness** (Audio page, under "Custom music folder";
  `audio.custom_music_level`, `RECOMP_AUDIO_CUSTOM_LEVEL`): `off`, `quieter`,
  `match` (default) or `louder`. A loudness chain, like a broadcast
  loudness processor, on the custom-soundtrack voices only (the voices the
  custom player starts; EA GAMES TRAX, speech and effects are not touched).
  It works on the song's samples before the title's own volume, fades and
  music slider (BO-246; the toolkit's `src/apu/apu_level.h`):
  - the song's K-weighted loudness (ITU-R BS.1770, the meter LUFS come
    from) over the last 3 s, read every 100 ms (a new song is first read
    after 0.3 s);
  - a gate: a reading under -50 LUFS, or more than 10 LU under the song's
    running level, holds the gain, so silence, a quiet intro, a breakdown
    or a fade out do not pull it around;
  - the running level is the song's own integrated loudness so far (gated
    like BS.1770's), started from the level the last song had. It settles
    as the song goes on; a breakdown four minutes in hardly moves it. A
    song that goes up a level for good (4 LU over for 2 s, the body after a
    long quiet intro) is counted again from there, and a quiet song after a
    loud one (10 to 20 LU under, louder than -24 LUFS, for 4 s at its
    start) is taken as the new level;
  - the gain brings that level to the target, -17 LUFS of the stream, which
    is about -20 LUFS in the game, the average of EA GAMES TRAX
    (`APU_LEVEL_TARGET_DB`); it moves with a 3 s time constant both ways,
    -20 to +15 dB;
  - a ceiling: the short-term output stays within 3 dB of the target. Over
    it the gain comes down with a 0.2 s time constant, so a song that comes
    in louder than the last one is down within about half a second;
  - a gentle compressor after it (2:1, 6 dB soft knee, 8 dB over the
    target, 10 ms attack, 150 ms release) only turns down what the slow
    gain has not caught yet. On a modern master it takes 0.02 dB on
    average.

  `quieter` and `louder` are 4 dB under and over `match`. `off` is no code
  at all: your songs are mixed as the title sends them. The first leveller
  (BO-132: an unweighted 3 s envelope, -15 to +6 dB, 0.3 s down and 4 s up)
  is still there for comparison: `RECOMP_AUDIO_CUSTOM_AGC=old`.
- **A safety peak limiter** on the final output (also on the fold of a 5.1 title
  to a stereo device), always on (the
  toolkit's `src/apu/apu_limit.h`; `RECOMP_AUDIO_SAFETY_LIMITER=0` switches it
  off for comparison): ceiling -0.5 dBFS, no look-ahead (no added
  latency), instant attack, 50 ms release, all channels linked, after the
  stereo fold or on the six channels. While nothing reaches the ceiling it does
  nothing and the output is bit for bit what it was without it
  (`tests/apu_bus`, with a recording of a race: 0 frames differ).

Measured (stereo, headless, `tools/headless/custom_level_scene.sh` and
`level_report.py`; four dance masters at -5.2 to -8.6 LUFS, the first, at -5.2
LUFS with sample peaks at +3 dBFS, playing; the menu has the music alone, the
race adds engine and effects; loudness is EBU R128 of the WAV the run kept):

| | menu, music alone | race: samples at full scale / within 0.5 dB of it | race true peak |
|---|---|---|---|
| EA GAMES TRAX | -19.2 LUFS here; -20.1 LUFS on average (-19.7, -23.1, -18.6, three songs) | 0 / 34 | -0.2 dBFS |
| custom, as before (off, no limiter) | -8.4 LUFS | 886 / 2805 | +0.6 dBFS |
| custom, off, safety limiter only | -8.4 LUFS (same bytes) | 0 / 298 | 0.0 dBFS |
| custom, match | -20.1 LUFS | 0 / 65 | -0.2 dBFS |

Off was 10.8 dB above the game's own music in the menu; match lands at its
average (-20.1 LUFS, the target constant set from that measurement; a song of
the player's own is a point, not a rule: EA GAMES TRAX's songs themselves
differ by 4 dB). A 5.1 title played on a stereo device folds its six feeds
(L = FL + 0.707 C + 0.707 SL); the limiter stands after that fold too, on the
16-bit sums, and the fold's gains are the game's own.

The loudness chain (BO-246), with `louder`, on a folder of nineties rave
(60 songs, -18.5 to -7.2 LUFS as files, loudness ranges up to 14.5 LU) and
modern techno (-9.3 to -6.7 LUFS):

| | quiet old masters (-19 to -17 LUFS as files) | the others | spread |
|---|---|---|---|
| headless, six whole songs in the menu, the chain before the ceiling | -16.1 to -15.5 LUFS | -15.3, -15.2, -14.6 | 1.5 LU |
| headless, the first minute of eight songs, quiet rave and loud techno in turn | -16.0 to -14.5 LUFS | -16.0 to -15.3 | 1.5 LU |
| offline (`tools/level_sim`), all 60 songs, the chain | within 1 LU of the median | | 1.8 LU |
| offline, all 60 songs, the first leveller | 0.5 to 1.4 LU under the median | | 2.6 LU |

With the first leveller the quiet songs fell behind for two reasons. Its
+6 dB limit held for 30 to 47 % of such a song, and after a loud song its
4 s rise (held while the level falls) left the first half minute 2.5 to 3
LU under. Without the ceiling, the chain let a loud song that followed a
quiet one play several dB too loud at its start (34 of the 60 songs more
than 3 dB over the target for over 2 s, up to +8.5 LU, offline). With
the ceiling, one of the 60 does, by at most 3.3 LU, and in the headless run
no second of a song start was more than 3.9 dB over. In the menu the safety
limiter touched 0.1 % of the samples, most of them in the loudest moments
of one song. The chain costs about 6 ns a sample per custom voice (0.03 %
of a core). In the same scene EA GAMES TRAX plays at -19.0 LUFS in the
menu; `match` lands at about -19.5 and `louder` at about -15.5.

`RECOMP_AUDIO_LEVEL_LOG=1` logs the readings, the gain, the compressor and the
safety limiter's count once a second.
`tools/headless/custom_level_scene.sh` plays copies of songs as a soundtrack
in a headless run and keeps the WAV; `tools/headless/level_report.py` reads it
(`--songs`: song by song). The toolkit's `tools/level_sim` runs the same code
offline over decoded songs.

## How it works

The title side, from the executable (addresses of the NTSC-U build):

| what | where |
|---|---|
| XDK soundtrack library: ST.DB block read, open, XFindNext/FirstSoundtrack, XGetSoundtrackSongInfo, XOpenSoundtrackSong | 0x001D0134, 0x001D0172, 0x001D0256 / 0x001D0275, 0x001D032C, 0x001D0554 |
| the EA GAMES TRAX screen counts and lists the soundtracks | sub_00155720 (set-up: also makes the music stream), sub_00155CB0 |
| a song's name for the list | sub_00084CF0, sub_001538F0 |
| the music player, once a frame | sub_00155900 |
| asks the file thread for song n of soundtrack s | sub_00155D60 -> sub_001B3E20; the thread: sub_001B3B40 |
| makes the WMA decoder for the opened handle | sub_00155DB0 -> sub_0030211F (WMADEC section) |
| next song: in order, or from a shuffled list of up to 500 | sub_00153660, sub_00153950 |

The player makes one DirectSound stream (PCM, 44.1 kHz, 16 bit, stereo) and,
for a user soundtrack, pulls 0x2000-byte packets from the song's WMA decoder
into it: `DoWork`, `GetStatus`, `Process`, and `Release` at the end. A packet
of 0 bytes ends the song. EA GAMES TRAX songs come through the same player
and stream, from the disc's own files.

With no database on the emulated disk (the case until now: the open of
`TDATA\FFFE0000\MUSIC\ST.DB` fails) the screen still shows NEXT SOUNDTRACK,
and X stays on EA GAMES TRAX.

The port (`core/soundtrack.c`, the toolkit's `src/soundtrack`,
`docs/runtime/soundtrack.md` there):

0. The overlay's row and folder list are the toolkit's
   (`xbox_OverlaySetMusicFolder`, the browser's model `xsb_*` in
   `src/soundtrack/xst_browse.c`); the port answers "chosen" and the status
   line (`core/soundtrack.c`).
1. At start, with a folder set, the toolkit scans it, writes the database to
   `<save dir>/TDATA/FFFE0000/MUSIC.HOST/ST.DB` and sends the title's `MUSIC`
   paths there. A `MUSIC` folder copied from a real console is not touched.
2. `sub_001D0554` (XOpenSoundtrackSong) is wrapped: the title's own code,
   then a note of which song the handle is.
3. `sub_0030211F` (the decoder for a handle) is wrapped: for one of the
   folder's songs the title gets an object whose ten methods are host
   functions (called through its vtable, at addresses 0xFE7F5700.. that
   `recomp_lookup_manual` answers); `Process` fills the title's packet from
   the host's decoder. For any other handle the title's own decoder is made.

Everything after the decoder is the title's: the stream and its mix bins
(stereo music, as EA GAMES TRAX; 5.1 is untouched), the music volume of the
Audio settings, pause, skip, shuffle.

4. `sub_00155420` (the title's start of the music of the chosen source) is
   wrapped for custom music at start: the title's own code, preceded by two
   reads of the manager's chosen source (+0x568): a value that is not the one
   last seen is the player's confirm in the EA GAMES TRAX screen, and is
   remembered by name; the first time, with the setting on and the manager
   counting the folder, the source is set to the remembered soundtrack.

A change while the game runs: the title counts the console's soundtracks
once, when its music manager is set up during boot (sub_00152E00 ->
sub_00155720), and reads everything else from the database each time: the
EA GAMES TRAX screen at every step (sub_00155CB0), the player at every song.
So after the new folder is scanned (a thread of its own) and its database is
in place, the port sets the two numbers the title keeps, at the manager
(0x004115E8): +0x0C0 the soundtracks counted and +0x558 the sources (that
plus one, EA GAMES TRAX being source 0). It does so only while the title is
on EA GAMES TRAX (+0x538 set, +0x568 the chosen source 0): a chosen
soundtrack is an index into the list that changes. Checked in a run: no
folder at boot, a folder chosen in the overlay, and the title's screen
listed its soundtracks at the next visit.

Why not real WMA files (the dashboard's way): it needs a WMA encoder, of
which there is none under a permissive licence (FFmpeg's is LGPL and large),
and an import step that re-encodes the whole library with a loss.

AAC: no decoder under a licence this project ships is small enough to vendor
(FAAD2 is GPL, FDK-AAC has its own licence, FFmpeg's is LGPL and large,
Android's old OpenCORE one is Apache but a hundred files). The operating
systems have one each; macOS's (AudioToolbox, ExtAudioFile) is used, since
that is where such libraries are. Windows (Media Foundation) and Android
(MediaCodec) could do the same; Linux has none to rely on.

## A soundtrack longer than EA GAMES TRAX (BO-120)

EA GAMES TRAX has 44 tracks, in a table at 0x3EC450 (24 bytes a track: the
pop-up's artist, title and album string indices and the modes the track may
play in). The title starts a track with sub_001537C0(index), which takes the
record at table + index * 24 and checks nothing. And it has ways to go from
a custom soundtrack back to EA GAMES TRAX with an index of the list it is
leaving: sub_00155420 picks the next index (sub_00153660: the one after the
last played, or a random one of the list's count) before it switches the
source; that is what runs after B (Cancel) in the EA GAMES TRAX screen once
X has shown a soundtrack. From a soundtrack of more than 44 songs the index
can be 44 or more. The record is then whatever lies after the table: the
pop-up (sub_001530D0, 0x153161) uses two of its words as string indices, and
for some indices (59 and 60 were seen) that is a wild address: the crash of
BO-120, with a 142-song folder. The same code is on the disc: a console with
a long soundtrack has the bug too.

`bo3_soundtrack_start_track` (the third wrapped function, sub_001537C0)
brings such an index into EA GAMES TRAX's range (index modulo its count)
before the title's code runs, and says so in the log once a few times
(`[SOUNDTRACK] EA GAMES TRAX was asked for track 97 of 44 ...`). It looks
only after a music folder has been in use in the run.

`tools/headless/custom_music_scene.sh <rundir>` is the check for all of
this: a made 142-song soundtrack, X, 59 rows down, cancel, the screen again,
random play, the soundtrack chosen, 30 s in the menu and 30 s of a race with
two skips; in 5.1 and with split-screen music on by default
(`SPEAKERS=stereo`, `SPLIT_MUSIC=0` for the others). It fails on a fault, a
dead game, or no song of the folder opened where one must be.

## With the setting empty

- `bo3_soundtrack_init` only gives the overlay its row; no folder is read,
  no path redirect is installed and no file is written.
- `sub_00155420` (the fourth wrapped function) does its two reads only while
  a library is in use (`s_on`); without a folder it calls the title's body
  and nothing else.
- The wrapped functions call the title's body and nothing else (the track
  start, sub_001537C0, is the one of the three the title reaches without a
  folder: it tests one flag and goes on). They are
  only reached while a user soundtrack plays, which needs a database: a run
  with a probe in all three entry points (boot, menus, the EA GAMES TRAX
  screen with X, a race, two skips, pause and resume) printed nothing.
- `recomp_lookup_manual`, asked at every indirect call, compares the address
  with 0xFE7F5700 first; no title code is above it.
- The generated code differs from before in the names of the two functions
  only (`sub_001D0554_gen`, `sub_0030211F_gen`).

The game's audio is not the same from run to run (two runs of one build
agree to the sample for the first 2.2 s of sound, then in 11 % of the
frames), so a capture cannot show identity by itself; build against build is
inside that same spread.

## Checking it

Unit tests: the toolkit's `tests/soundtrack` (scan, names, ST.DB, decoders,
soundtrack name and lookup by name) and `tests/overlay_settings` (the text
setting, the empty value kept for `audio.custom_music_soundtrack`).

`tools/headless/custom_start_scene.sh` is the check for custom music at
start: a made folder of three soundtracks, a scratch HOME and settings file;
`STEP=menu` shows which soundtrack the title opened in the menu, `STEP=pick`
chooses one in the EA GAMES TRAX screen and reads the settings file,
`STEP=race` shows the first race's songs.

A run: make a folder with a 1 kHz sine in it, start with
`RECOMP_AUDIO_MUSIC_DIR=<folder> RECOMP_AUDIO_WAV=<file>` (scratch `HOME`,
`RECOMP_SAVE_DIR` and `RECOMP_SETTINGS=none`, as for every test run), choose
the soundtrack in EA GAMES TRAX and start a race: the log has a
`[SOUNDTRACK] song ...` line for each song the title opens, and the WAV's
spectrum the tone. Measured on macOS: a sine at -9.0 dBFS RMS in the file
comes out at -10.4 dBFS in the menu and in the race at the title's default
music volume, 99 % of the power at 1 kHz between engine sounds.

## Android

Done with way 1 below (2026-10-13): the row asks for `READ_MEDIA_AUDIO`
through SDL_AndroidRequestPermission the first time it is opened, on its own
thread so the menu keeps drawing; places that cannot be listed are left out,
and a chosen folder that cannot be read leaves the game's own music playing
with a status line. The two ways that were weighed:

1. Shared storage as files (the smaller one): `READ_MEDIA_AUDIO` (Android
   13+; `READ_EXTERNAL_STORAGE` before) in the manifest and asked for at
   run time from the game's activity when the row is opened. With it, audio
   files under /storage/emulated/0 and a card's /storage/<id> are ordinary
   paths, which is what the browser's Android places already list and the
   decoders already read. Left: the manifest line, the request (Java, in the
   SDL activity, called through JNI from the port's "chosen"/open hook), and
   a run on a device.
2. The document-tree picker (SAF), the system's own folder dialog: an
   activity like the driver page's (`ACTION_OPEN_DOCUMENT_TREE`,
   `takePersistableUriPermission`), the tree URI stored as the setting, the
   scan through `DocumentsContract` child queries (Java, handed to native as
   a list), and the decoders opened on file descriptors
   (`ContentResolver.openFileDescriptor` -> `fdopen`; dr_libs and stb_vorbis
   take callbacks or a `FILE *`). It needs no storage permission, but paths
   stop being paths: `xst_song.path` becomes a URI and every open goes
   through JNI. About two days with a device to test on.

## Not done

- Android: played by the owner on a Retroid Pocket 5 with his own folder;
  the permission prompt's deny path was not tried on a device. Windows and Linux are compiled (Windows: cross-compiled)
  but not run: the drive letters, /run/media and the Deck's SD card are in
  the browser's model and its unit test, not seen on a device.
- Folder names in the overlay's list: Latin (Central European, Baltic and
  Turkish letters included), Greek and Cyrillic are drawn; other scripts
  (CJK, Arabic ...) show as squares, though the folder still works (the
  toolkit's docs/runtime/overlay.md, "Text and fonts"). In the title's own
  menu names stay folded to Latin-1.
- m4a outside macOS.
- Real libraries: long playlists, odd tags, slow or network disks (the scan
  at start waits for the folder).
- The EA GAMES TRAX pop-up did not show for a user's song in a race (the
  title's own behaviour, as far as seen).
- The shader pre-build's runs read the setting too; they need not.
