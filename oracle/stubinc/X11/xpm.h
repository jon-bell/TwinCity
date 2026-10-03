/* Minimal libXpm 3.5 client header (libxpm-dev not installed). Struct layout per libXpm 3.5.x xpm.h. */
#ifndef XPM_h
#define XPM_h
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#define XpmFormat 3
#define XpmVersion 4
#define XpmRevision 11
#define XpmColorError 1
#define XpmSuccess 0
#define XpmOpenFailed -1
#define XpmFileInvalid -2
#define XpmNoMemory -3
#define XpmColorFailed -4
typedef unsigned long Pixel;
typedef struct { char *name; char *value; Pixel pixel; } XpmColorSymbol;
typedef struct { char *name; unsigned int nlines; char **lines; } XpmExtension;
typedef struct { char *string; char *symbolic; char *m_color; char *g4_color; char *g_color; char *c_color; } XpmColor;
typedef int (*XpmAllocColorFunc)(Display*, Colormap, char*, XColor*, void*);
typedef int (*XpmFreeColorsFunc)(Display*, Colormap, Pixel*, int, void*);
typedef struct {
  unsigned long valuemask; Visual *visual; Colormap colormap; unsigned int depth;
  unsigned int width; unsigned int height; unsigned int x_hotspot; unsigned int y_hotspot;
  unsigned int cpp; Pixel *pixels; unsigned int npixels; XpmColorSymbol *colorsymbols;
  unsigned int numsymbols; char *rgb_fname; unsigned int nextensions; XpmExtension *extensions;
  unsigned int ncolors; XpmColor *colorTable; char *hints_cmt; char *colors_cmt; char *pixels_cmt;
  unsigned int mask_pixel; Bool exactColors; unsigned int closeness; unsigned int red_closeness;
  unsigned int green_closeness; unsigned int blue_closeness; int color_key; Pixel *alloc_pixels;
  int nalloc_pixels; Bool alloc_close_colors; int bitmap_format; XpmAllocColorFunc alloc_color;
  XpmFreeColorsFunc free_colors; void *color_closure;
} XpmAttributes;
#define XpmVisual (1L<<0)
#define XpmColormap (1L<<1)
#define XpmDepth (1L<<2)
#define XpmSize (1L<<3)
#define XpmHotspot (1L<<4)
#define XpmCharsPerPixel (1L<<5)
#define XpmColorSymbols (1L<<6)
#define XpmRgbFilename (1L<<7)
#define XpmInfos (1L<<8)
#define XpmReturnInfos XpmInfos
#define XpmReturnPixels (1L<<9)
#define XpmExtensions (1L<<10)
#define XpmReturnExtensions XpmExtensions
#define XpmExactColors (1L<<11)
#define XpmCloseness (1L<<12)
int XpmReadFileToPixmap(Display*, Drawable, const char*, Pixmap*, Pixmap*, XpmAttributes*);
int XpmCreatePixmapFromData(Display*, Drawable, char**, Pixmap*, Pixmap*, XpmAttributes*);
void XpmFreeAttributes(XpmAttributes*);
#endif
