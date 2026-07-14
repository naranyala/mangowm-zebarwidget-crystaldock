#include "toplevel.h"
#include <string.h>

int toplevel_find(struct toplevel_info *infos, int count, const void *handle) {
  for (int i = 0; i < count; i++)
    if (infos[i].handle == handle) return i;
  return -1;
}

int toplevel_add(struct toplevel_info *infos, int *count, const void *handle) {
  if (*count >= MAX_TOPLEVELS) return -1;
  struct toplevel_info *info = &infos[(*count)++];
  memset(info, 0, sizeof(*info));
  info->handle = (void*)handle;
  return *count - 1;
}

void toplevel_remove_at(struct toplevel_info *infos, int *count, int idx) {
  if (idx < 0 || idx >= *count) return;
  (*count)--;
  for (int i = idx; i < *count; i++)
    infos[i] = infos[i + 1];
  memset(&infos[*count], 0, sizeof(struct toplevel_info));
}
