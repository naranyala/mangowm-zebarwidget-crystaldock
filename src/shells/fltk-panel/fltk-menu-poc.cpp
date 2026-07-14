// FLTK menu proof-of-concept.
// Goal: compare a "real FLTK window" popup menu against the native
// Wayland popup menu implemented in menu.cpp.
//
// NOTE: this project builds FLTK Wayland-only, and fl_open_display()
// is known to hang under the target compositor (labwc). If it hangs,
// `timeout` below will kill it -- that *is* the comparison result.
#include <FL/Fl.H>
#include <FL/Fl_Window.H>
#include <FL/Fl_Menu_Button.H>
#include <stdio.h>

int main(int argc, char **argv) {
  printf("FLTK PoC: creating window...\n"); fflush(stdout);
  Fl_Window win(220, 160, "FLTK Menu (PoC)");
  Fl_Menu_Button menu(10, 10, 200, 30, "Menu");
  menu.add("Applications/Terminal");
  menu.add("Applications/Files");
  menu.add("Power/Suspend");
  menu.add("Power/Shutdown");
  win.end();
  win.show(argc, argv);
  printf("FLTK PoC: window shown, entering run loop (this may hang)...\n"); fflush(stdout);
  return Fl::run();
}
