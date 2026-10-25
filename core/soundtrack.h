/*
 * soundtrack.h - the user's music folder in the title's EA GAMES TRAX
 * screen (BO-108, docs/custom-music.md).
 *
 * The title plays Xbox custom soundtracks: its XDK soundtrack library reads
 * the dashboard's database and its music player decodes the songs with the
 * XDK's WMA decoder. With audio.custom_music_dir set, the toolkit's
 * xbox_soundtrack makes that database from the folder, and the two guest
 * functions below (wrapped in recomp/recomp_manual.c) hand the title's
 * player a decoder that the host answers. With the setting empty (the
 * default) both run the title's own code and nothing else.
 */
#ifndef BO3_SOUNDTRACK_H
#define BO3_SOUNDTRACK_H

#include <stdint.h>

typedef void (*bo3_guest_fn)(void);

/* After xbox_path_init, before the title starts: scan the folder
 * (RECOMP_AUDIO_MUSIC_DIR / audio.custom_music_dir / --music-dir). */
void bo3_soundtrack_init(void);

/* sub_001D0554, XOpenSoundtrackSong(song id, async): the title's own, and a
 * note of which song the handle it returned is. */
void bo3_soundtrack_open_song(bo3_guest_fn title_fn);
/* sub_0030211F, the WMA decoder for an open file: the host's decoder for one
 * of the folder's songs, the title's own for anything else. */
void bo3_soundtrack_create_decoder(bo3_guest_fn title_fn);
/* sub_001537C0, the title's "start track n of the source in use": an index
 * EA GAMES TRAX's table does not have (one left from a longer custom list)
 * is brought into range first (BO-120); then the title's own. */
void bo3_soundtrack_start_track(bo3_guest_fn title_fn);
/* sub_00155420, the title's "start the music of the source chosen"
 * (stdcall, the manager): where the title reads which source (EA GAMES TRAX
 * or soundtrack n) the player chose, and starts a track of it. Here
 * (BO-230): the source the player confirmed in the EA GAMES TRAX screen is
 * remembered by name (audio.custom_music_soundtrack), and, once per run,
 * with a folder set and audio.custom_music_at_start on, the title is put on
 * the remembered soundtrack before the title's own code reads the source.
 * With no folder it runs the title's body and nothing else. */
void bo3_soundtrack_start_source(bo3_guest_fn title_fn);
/* recomp_lookup_manual: the methods of that decoder object, called through
 * its vtable; NULL for every other address. */
bo3_guest_fn bo3_soundtrack_lookup(uint32_t xbox_va);

/* The addresses the decoder object's vtable holds: above the kernel thunks'
 * and below the APU's registers, where the title has no code. */
#define BO3_SOUNDTRACK_VA_BASE 0xFE7F5700u
#define BO3_SOUNDTRACK_VA_END  (BO3_SOUNDTRACK_VA_BASE + 10 * 4)

#endif /* BO3_SOUNDTRACK_H */
