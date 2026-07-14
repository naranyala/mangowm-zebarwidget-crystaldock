// dock_c_impl.c — Includes all real C headers for linking
// Compiles separately from Zig; Zig only sees dock_c.h declarations.

#include <wayland-client.h>
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include <librsvg/rsvg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/poll.h>
#include <time.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

// Anonymous shared memory helper
int dock_create_shm_fd(size_t size) {
    char name[] = "/tmp/wl_shm-XXXXXX";
    int fd = mkstemp(name);
    if (fd < 0) return -1;
    unlink(name);
    if (ftruncate(fd, (off_t)size) < 0) { close(fd); return -1; }
    return fd;
}
