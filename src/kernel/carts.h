/*
 * Cartridges on the SD card (/ and /bm and /bme): initialization, listing,
 * and execution from the shell or over serial/network.
 */
#ifndef CARTS_H
#define CARTS_H

#include <stddef.h>
#include <stdint.h>
#include "drivers/fb.h"

/* Initialises the SD card, mounts FAT, and scans for .bm/.bme files. */
void carts_init(void);

/* Number of cartridges found on the SD card after carts_init. */
int carts_count(void);

/* Prints the list of cartridges on the console. */
void carts_list(void);

/* Plays the cartridge matching this title, file name, or path; -1 if none. */
int carts_play_title(framebuffer_t *fb, const char *name);

/* Plays a cartridge image in memory (a .bm, by its magic). */
void carts_play_buffer(framebuffer_t *fb, const uint8_t *data, size_t len);

#endif
