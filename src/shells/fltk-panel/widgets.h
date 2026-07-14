#pragma once
#include "widget.h"

#ifdef __cplusplus
extern "C" {
#endif

widget_t *w_workspaces_create(const char *opts);
widget_t *w_toplevel_create(const char *opts);
widget_t *w_launcher_create(const char *opts);
widget_t *w_cpu_create(const char *opts);
widget_t *w_mem_create(const char *opts);
widget_t *w_temp_create(const char *opts);
widget_t *w_disk_create(const char *opts);
widget_t *w_battery_create(const char *opts);
widget_t *w_volume_create(const char *opts);
widget_t *w_network_create(const char *opts);
widget_t *w_media_create(const char *opts);
widget_t *w_clock_create(const char *opts);
widget_t *w_power_create(const char *opts);
widget_t *w_settings_create(const char *opts);

widget_t **config_load_widgets(const char *path, int *out_count);

#ifdef __cplusplus
}
#endif
