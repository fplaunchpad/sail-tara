/* Program images, loaded into the machine from address 0: raw bytes (.bin),
 * or big-endian 16-bit words of 1 to 4 hex digits (.hex), where ';' starts a
 * comment. */
#ifndef TARA_IMAGE_H
#define TARA_IMAGE_H

#include <stdbool.h>

/* Load the image at path; on failure, print why to stderr and return false. */
bool image_load(const char *path);

#endif
