#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_TOPLEVELS 64

struct toplevel_info {
  void *handle;
  char title[256];
  char app_id[128];
  uint32_t id;
  bool focused, minimized, maximized;
};

int toplevel_find(struct toplevel_info *infos, int count, const void *handle);
int toplevel_add(struct toplevel_info *infos, int *count, const void *handle);
void toplevel_remove_at(struct toplevel_info *infos, int *count, int idx);

#ifdef __cplusplus
}
#endif
