/* Minimal libXext MIT-SHM client header (libxext-dev not installed). ABI per libXext 1.3. */
#ifndef _XSHM_H_
#define _XSHM_H_
#include <X11/Xlib.h>
#include <X11/extensions/shm.h>
typedef unsigned long ShmSeg;
typedef struct { ShmSeg shmseg; int shmid; char *shmaddr; Bool readOnly; } XShmSegmentInfo;
Bool XShmQueryExtension(Display*);
int XShmGetEventBase(Display*);
Bool XShmQueryVersion(Display*, int*, int*, Bool*);
int XShmPixmapFormat(Display*);
Bool XShmAttach(Display*, XShmSegmentInfo*);
Bool XShmDetach(Display*, XShmSegmentInfo*);
Bool XShmPutImage(Display*, Drawable, GC, XImage*, int, int, int, int, unsigned int, unsigned int, Bool);
Bool XShmGetImage(Display*, Drawable, XImage*, int, int, unsigned long);
XImage *XShmCreateImage(Display*, Visual*, unsigned int, int, char*, XShmSegmentInfo*, unsigned int, unsigned int);
Pixmap XShmCreatePixmap(Display*, Drawable, char*, XShmSegmentInfo*, unsigned int, unsigned int, unsigned int);
#endif
