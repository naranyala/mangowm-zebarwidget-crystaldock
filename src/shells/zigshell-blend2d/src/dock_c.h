// dock_c.h — Combined header for Zig @cImport (Blend2D version)
// Includes real Wayland protocol headers and Blend2D C API.
// Replaces Cairo/Pango/librsvg with Blend2D.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <ctype.h>
#include <sys/statvfs.h>

// Real Wayland headers (self-contained, no glib dependency)
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

// Blend2D C API
#include "blend2d/blend2d.h"

// Blend2D rendering abstraction
#include "blend2d_render.h"

// Icon loading
#include "icon.h"

// Dock rendering
#include "dock.h"

// Panel draw functions
#include "panel_draw.h"

// Utility
int dock_create_shm_fd(size_t size);
