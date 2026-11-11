#ifndef VOS_MINGW_COMPAT_H
#define VOS_MINGW_COMPAT_H

#if defined(__MINGW32__) && defined(__GNUC__)
// MinGW maps _mm_malloc to _aligned_malloc, which V declares before intrinsics.
#define _MM_MALLOC_H_INCLUDED
#endif

#endif
