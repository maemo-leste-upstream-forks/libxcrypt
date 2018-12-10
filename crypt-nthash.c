/*-
 * Copyright (c) 2003 Michael Bretterklieber
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The bogus 'gensalt_nt_rn' function and all modifications to the other
 * parts of this file are
 *
 * Copyright (c) 2017 Björn Esser <besser82@fedoraproject.org>
 * All rights reserved.
 *
 * and is provided under the same licensing terms and conditions as the
 * other parts of this file.
 */

#include "crypt-port.h"
#include "alg-md4.h"

#include <errno.h>
#include <stdlib.h>
#include <netinet/in.h>

#if INCLUDE_nt

/*
 * NT HASH = md4(str2unicode(phrase))
 */

void
crypt_nt_rn (const char *phrase, size_t ARG_UNUSED (phr_size),
             const char *setting, size_t ARG_UNUSED (set_size),
             uint8_t *output, size_t out_size,
             void *scratch, size_t scr_size)
{
  size_t unipwLen;
  int i;
  static const char hexconvtab[] = "0123456789abcdef";
  static const char *magic = "$3$";
  uint16_t unipw[128];
  unsigned char hash[16];
  const char *s;
  MD4_CTX *ctx = scratch;

  if ((out_size < 4 + 32) ||
      (scr_size < sizeof (MD4_CTX)))
    {
      errno = ERANGE;
      return;
    }

  if (strncmp (setting, magic, strlen (magic)))
    {
      errno = EINVAL;
      return;
    }

  XCRYPT_SECURE_MEMSET (unipw, sizeof unipw);
  /* convert to unicode (thanx Archie) */
  unipwLen = 0;
  for (s = phrase; unipwLen < sizeof(unipw) / 2 && *s; s++)
    unipw[unipwLen++] = htons((uint16_t)(*s << 8));

  /* Compute MD4 of Unicode password */
  MD4_Init (ctx);
  MD4_Update (ctx, unipw, unipwLen*sizeof(uint16_t));
  MD4_Final (hash, ctx);

  output += XCRYPT_STRCPY_OR_ABORT (output, out_size, magic);
  *output++ = '$';
  for (i = 0; i < 16; i++)
    {
      *output++ = (uint8_t)hexconvtab[hash[i] >> 4];
      *output++ = (uint8_t)hexconvtab[hash[i] & 0xf];
    }
  *output = '\0';
}

/* This function simply returns the magic string '$3$',
   so it can be used as SETTING for the crypt function.  */
void
gensalt_nt_rn (unsigned long count,
               ARG_UNUSED(const uint8_t *rbytes),
               ARG_UNUSED(size_t nrbytes),
               uint8_t *output,
               size_t o_size)
{
  const char *prefix = "$3$";

  /* Minimal O_SIZE to store the prefix.  */
  if (o_size < strlen (prefix) + 1)
    {
      errno = ERANGE;
      return;
    }

  if (count != 0)
    {
      errno = EINVAL;
      return;
    }

  XCRYPT_STRCPY_OR_ABORT (output, o_size, prefix);
}

#endif
