/*********************************************************************
* Filename:   des.h
* Author:     Brad Conte (brad AT bradconte.com)
* Copyright:
* Disclaimer: This code is presented "as is" without any guarantees.
* Details:    Defines the API for the corresponding DES implementation.
              Note that encryption and decryption are defined by how
              the key setup is performed, the actual en/de-cryption is
              performed by the same function.
*********************************************************************/

#ifndef DATELYRICS_QRC_DES_H
#define DATELYRICS_QRC_DES_H

/*************************** HEADER FILES ***************************/
#include <stddef.h>

/****************************** MACROS ******************************/
#define DES_BLOCK_SIZE 8                // DES operates on 8 bytes at a time

/**************************** DATA TYPES ****************************/
typedef unsigned char DateLyricsQRCByte;             // 8-bit byte
typedef unsigned int  DateLyricsQRCWord;             // 32-bit word, change to "long" for 16-bit machines

typedef enum {
	DateLyricsQRCEncrypt,
	DateLyricsQRCDecrypt
} DateLyricsQRCMode;

/*********************** FUNCTION DECLARATIONS **********************/
void DateLyricsQRCDesKeySetup(const DateLyricsQRCByte key[], DateLyricsQRCByte schedule[][6], DateLyricsQRCMode mode);
void DateLyricsQRCDesCrypt(const DateLyricsQRCByte in[], DateLyricsQRCByte out[], const DateLyricsQRCByte key[][6]);

void DateLyricsQRCKeySetup(const DateLyricsQRCByte key[], DateLyricsQRCByte schedule[][16][6], DateLyricsQRCMode mode);
void DateLyricsQRCDecryptBlock(const DateLyricsQRCByte in[], DateLyricsQRCByte out[], const DateLyricsQRCByte key[][16][6]);

#endif   // DES_H
