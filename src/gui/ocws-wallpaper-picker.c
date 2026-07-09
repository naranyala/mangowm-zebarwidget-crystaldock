#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tinyfiledialogs.h"

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    char const * lFilterPatterns[4] = { "*.jpg", "*.png", "*.jpeg", "*.webp" };
    char const * lTheOpenFileName;

    lTheOpenFileName = tinyfd_openFileDialog(
        "Select Wallpaper",
        "",
        4,
        lFilterPatterns,
        "Image Files",
        0);

    if (!lTheOpenFileName) {
        fprintf(stderr, "No file selected.\n");
        return 1;
    }

    printf("Selected wallpaper: %s\n", lTheOpenFileName);

    // Apply the wallpaper using swaybg (kill existing, start new)
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "killall swaybg 2>/dev/null; swaybg -i \"%s\" -m fill &", lTheOpenFileName);
    printf("Executing: %s\n", cmd);
    int ret = system(cmd);
    
    // Attempt to generate theme from wallpaper if the script is available
    snprintf(cmd, sizeof(cmd), "wallpaper-theme.sh \"%s\" || true", lTheOpenFileName);
    system(cmd);

    return ret == 0 ? 0 : 1;
}
