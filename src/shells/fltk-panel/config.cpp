#include "widgets.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <glib.h>

widget_t **config_load_widgets(const char *path, int *out_count) {
  widget_t **list = NULL;
  int count = 0, cap = 0;

  char *data = NULL;
  gsize len = 0;
  if (!g_file_get_contents(path, &data, &len, NULL)) {
    *out_count = 0;
    return NULL;
  }

  char *opts = (char*)malloc(1);
  opts[0] = 0;
  char cur_type[64];
  cur_type[0] = 0;

  char *line = strtok(data, "\n");
  while (line) {
    while (*line == ' ' || *line == '\t' || *line == '\r') line++;
    if (*line == 0 || *line == '#') { line = strtok(NULL, "\n"); continue; }

    if (*line == '[') {
      char *end = strchr(line, ']');
      if (end) {
        *end = 0;
        // finalize the previous section
        if (cur_type[0]) {
          widget_t *w = widget_create(cur_type, opts);
          if (w) {
            if (count >= cap) {
              cap = cap ? cap * 2 : 8;
              list = (widget_t**)realloc(list, cap * sizeof(widget_t*));
            }
            list[count++] = w;
          }
        }
        // start accumulating the new section
        free(opts);
        opts = (char*)malloc(1);
        opts[0] = 0;
        snprintf(cur_type, sizeof(cur_type), "%s", line + 1);
      }
    } else {
      size_t ol = strlen(opts);
      size_t ll = strlen(line);
      char *tmp = (char*)realloc(opts, ol + ll + 2);
      if (tmp) {
        opts = tmp;
        if (ol) strcat(opts, "\n");
        strcat(opts, line);
      }
    }
    line = strtok(NULL, "\n");
  }

  // finalize the last section
  if (cur_type[0]) {
    widget_t *w = widget_create(cur_type, opts);
    if (w) {
      if (count >= cap) {
        cap = cap ? cap * 2 : 8;
        list = (widget_t**)realloc(list, cap * sizeof(widget_t*));
      }
      list[count++] = w;
    }
  }

  free(opts);
  g_free(data);
  *out_count = count;
  return list;
}
