/* Program images, loaded into the machine from address 0, at most 2048 bytes. The suffix of the
 * file name selects the format:
 *   .bin  raw bytes;
 *   .hex  big-endian 16-bit words of 1 to 4 hex digits in either case, separated by whitespace,
 *         with ';' starting a comment that runs to the end of the line. */
#ifndef TARA_IMAGE_H
#define TARA_IMAGE_H

#include <stdbool.h>

/* Load the image at path; on failure, print why to stderr and return false. */
bool load_program(const char *path);

#endif
