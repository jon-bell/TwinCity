/* Minimal libXext SHAPE client header (libxext-dev not installed). */
#ifndef _SHAPE_H_
#define _SHAPE_H_
#include <X11/Xlib.h>
#include <X11/extensions/shapeconst.h>
Bool XShapeQueryExtension(Display*, int*, int*);
void XShapeCombineMask(Display*, Window, int, int, int, Pixmap, int);
void XShapeCombineRectangles(Display*, Window, int, int, int, XRectangle*, int, int, int);
#endif
