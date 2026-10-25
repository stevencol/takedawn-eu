/*
 * gp_image.h -- the title's GP effects image, sound/DSP/B3XboxFx.bin, as
 * the APU's model of it is wired (apu_gp.h): which effect sits on which
 * mixbin and where the GP program copies the bins for the title's return
 * voices. docs/audio-gp.md has the whole picture.
 */
#ifndef BO3_GP_IMAGE_H
#define BO3_GP_IMAGE_H

/* Call before the APU starts. */
void bo3_gp_wire(void);

#endif
