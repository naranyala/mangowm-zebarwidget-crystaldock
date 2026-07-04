#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <stdbool.h>
#include <sys/stat.h>

#define RED     "\033[0;31m"
#define GREEN   "\033[0;32m"
#define YELLOW  "\033[1;33m"
#define CYAN    "\033[0;36m"
#define BOLD    "\033[1m"
#define NC      "\033[0m"

void pass(const char *msg) { printf("%s✓%s %s\n", GREEN, NC, msg); }
void fail(const char *msg) { printf("%s✗%s %s\n", RED, NC, msg); exit(1); }
void info(const char *msg) { printf("%s→%s %s\n", CYAN, NC, msg); }

bool check_cmd(const char *cmd) {
    char buf[256];
    snprintf(buf, sizeof(buf), "command -v %s >/dev/null 2>&1", cmd);
    return system(buf) == 0;
}

void get_timestamp(char *buf, size_t size) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(buf, size, "%Y%m%d-%H%M%S", t);
}

void ensure_dir(const char *dir) {
    struct stat st = {0};
    if (stat(dir, &st) == -1) {
        mkdir(dir, 0700); // Only user has rwx
    }
}

void sanitize_filename(char *dest, const char *src, size_t max_len) {
    size_t i = 0;
    while (src[i] != '\0' && i < max_len - 1) {
        if ((src[i] >= 'a' && src[i] <= 'z') ||
            (src[i] >= 'A' && src[i] <= 'Z') ||
            (src[i] >= '0' && src[i] <= '9') ||
            src[i] == '-' || src[i] == '_' || src[i] == '.') {
            dest[i] = src[i];
        } else {
            dest[i] = '-';
        }
        i++;
    }
    dest[i] = '\0';
}

void get_save_path(char *path, size_t size, const char *prefix) {
    char ts[32];
    get_timestamp(ts, sizeof(ts));
    char save_dir[256];
    snprintf(save_dir, sizeof(save_dir), "%s/Pictures/screenshots", getenv("HOME"));
    ensure_dir(save_dir);
    
    const char *safe_prefix = prefix;
    if (prefix) {
        char safe_prefix_buf[64];
        sanitize_filename(safe_prefix_buf, prefix, sizeof(safe_prefix_buf));
        safe_prefix = safe_prefix_buf;
    }
    
    snprintf(path, size, "%s/%s-%s.png", save_dir, safe_prefix, ts);
}

void annotate(const char *src) {
    bool has_satty = check_cmd("satty");
    bool has_swappy = check_cmd("swappy");
    char cmd[512];

    if (has_satty) {
        snprintf(cmd, sizeof(cmd), "satty --filename \"%s\" --output-filename \"%s\" --copy-command wl-copy 2>/dev/null", src, src);
        system(cmd);
    } else if (has_swappy) {
        snprintf(cmd, sizeof(cmd), "swappy -f \"%s\" -o \"%s\" 2>/dev/null", src, src);
        system(cmd);
    } else {
        info("Install satty or swappy for annotation support");
    }
}

void copy_to_clipboard(const char *file) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "wl-copy < \"%s\"", file);
    system(cmd);
}

void take_area(bool do_annotate) {
    if (!check_cmd("grim") || !check_cmd("slurp")) fail("Need grim + slurp. Install: sudo apt install grim slurp");
    
    char file[512];
    get_save_path(file, sizeof(file), "screenshot-area");
    
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "grim -g \"$(slurp)\" \"%s\" 2>/dev/null", file);
    if (system(cmd) != 0) fail("Selection cancelled or failed");
    
    if (do_annotate) {
        annotate(file);
        pass("Area annotated");
    } else {
        copy_to_clipboard(file);
        pass("Area saved");
    }
}

void take_full(bool do_annotate) {
    if (!check_cmd("grim")) fail("Need grim. Install: sudo apt install grim");
    
    char file[512];
    get_save_path(file, sizeof(file), "screenshot-full");
    
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "grim \"%s\" 2>/dev/null", file);
    if (system(cmd) != 0) fail("Screenshot failed");
    
    if (do_annotate) {
        annotate(file);
        pass("Full annotated");
    } else {
        copy_to_clipboard(file);
        pass("Full screen saved");
    }
}

void take_window() {
    if (!check_cmd("grim")) fail("Need grim. Install: sudo apt install grim");
    
    char cmd[1024];
    FILE *fp;
    char geo[256] = {0};
    
    if (check_cmd("swaymsg") && check_cmd("jq")) {
        fp = popen("swaymsg -t get_tree | jq -r '.. | select(.type?) | select(.focused==true) | .rect | \"\\(.x),\\(.y) \\(.width)x\\(.height)\"' 2>/dev/null", "r");
        if (fp != NULL) {
            if (fgets(geo, sizeof(geo)-1, fp) != NULL) {
                geo[strcspn(geo, "\n")] = 0;
            }
            pclose(fp);
        }
    }
    
    if (strlen(geo) > 0) {
        char file[512];
        get_save_path(file, sizeof(file), "screenshot-window");
        
        snprintf(cmd, sizeof(cmd), "grim -g \"%s\" -t format=png \"%s\" 2>/dev/null", geo, file);
        if (system(cmd) != 0) fail("Window capture failed");
        
        copy_to_clipboard(file);
        pass("Window saved");
    } else {
        info("Could not detect window — falling back to area select");
        take_area(false);
    }
}

void take_delay(int delay_secs) {
    if (!check_cmd("grim")) fail("Need grim.");
    printf("%s→%s Taking screenshot in %ds...\n", CYAN, NC, delay_secs);
    sleep(delay_secs);
    take_full(false);
}

void show_menu() {
    printf("\n%sScreenshot Menu%s\n\n", BOLD, NC);
    printf("  1) Area select\n");
    printf("  2) Full screen\n");
    printf("  3) Active window\n");
    printf("  4) Area → annotate\n");
    printf("  5) Full screen → annotate\n");
    printf("  6) Full screen (3s delay)\n\n");
    printf("Choice [1-6]: ");
    
    char choice[16];
    if (fgets(choice, sizeof(choice), stdin)) {
        int c = atoi(choice);
        switch (c) {
            case 1: take_area(false); break;
            case 2: take_full(false); break;
            case 3: take_window(); break;
            case 4: take_area(true); break;
            case 5: take_full(true); break;
            case 6: take_delay(3); break;
            default: fail("Invalid choice");
        }
    }
}

int main(int argc, char *argv[]) {
    const char *mode = "menu";
    if (argc > 1) mode = argv[1];
    
    if (strcmp(mode, "area") == 0) {
        take_area(false);
    } else if (strcmp(mode, "full") == 0) {
        take_full(false);
    } else if (strcmp(mode, "window") == 0) {
        take_window();
    } else if (strcmp(mode, "area-annotate") == 0) {
        take_area(true);
    } else if (strcmp(mode, "full-annotate") == 0) {
        take_full(true);
    } else if (strcmp(mode, "delay") == 0) {
        int delay_secs = 3;
        if (argc > 2) delay_secs = atoi(argv[2]);
        take_delay(delay_secs);
    } else if (strcmp(mode, "menu") == 0) {
        show_menu();
    } else if (strcmp(mode, "--help") == 0 || strcmp(mode, "-h") == 0) {
        printf("Usage: %s [area|full|window|area-annotate|full-annotate|delay [N]|menu]\n", argv[0]);
    } else {
        fail("Unknown mode");
    }
    return 0;
}
