FLTK_DIR = ../../../sources/fltk
FLTK_BUILD = $(FLTK_DIR)/build
FLTK_CONFIG = $(FLTK_BUILD)/fltk-config

CXX ?= g++
CXXFLAGS := $(shell $(FLTK_CONFIG) --cxxflags) -I. -g -O2 $(shell pkg-config --cflags pangocairo glib-2.0)
LIBS := $(shell $(FLTK_CONFIG) --ldflags) -lwayland-client -lcairo -lpangocairo-1.0 -lm $(shell pkg-config --libs glib-2.0)
LDFLAGS = -Wl,-rpath,$(abspath $(FLTK_BUILD)/lib)

SHELL_OBJS = shell.o shm.o toplevel.o render.o widget.o widgets.o config.o menu.o dock-render.o icon.o
SHELL_LIBS = $(shell pkg-config --libs librsvg-2.0)
PROTO_OBJS = wlr-layer-shell-unstable-v1-client-protocol.o \
             wlr-foreign-toplevel-management-unstable-v1-client-protocol.o \
             xdg-shell-client-protocol.o
OBJS = $(SHELL_OBJS) $(PROTO_OBJS)

all: fltk-cpp-shell tests

fltk-cpp-shell: $(SHELL_OBJS) $(PROTO_OBJS)
	$(CXX) $(LDFLAGS) -o $@ $(SHELL_OBJS) $(PROTO_OBJS) $(LIBS) $(SHELL_LIBS)

shell.o: shell.cpp shm.h toplevel.h render.h widget.h widgets.h menu.h dock-render.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

shm.o: shm.c shm.h
	$(CC) -std=gnu11 -c -o $@ $< $(shell pkg-config --cflags glib-2.0)

toplevel.o: toplevel.cpp toplevel.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

render.o: render.cpp render.h toplevel.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

widget.o: widget.cpp widget.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

widgets.o: widgets.cpp widgets.h widget.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

config.o: config.cpp widgets.h widget.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

menu.o: menu.cpp menu.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

icon.o: icon.cpp icon.h
	$(CXX) $(CXXFLAGS) $(shell pkg-config --cflags librsvg-2.0) -c -o $@ $<

dock-render.o: dock-render.cpp dock-render.h icon.h toplevel.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

%-client-protocol.o: %-client-protocol.c
	$(CC) -c -o $@ $< $(shell pkg-config --cflags wayland-client)

run: fltk-cpp-shell
	./fltk-cpp-shell

# --- tests ---

TEST_DIR = tests
TEST_CXXFLAGS = -I. -g -O0 $(shell pkg-config --cflags pangocairo glib-2.0)
TEST_LIBS = $(shell pkg-config --libs pangocairo glib-2.0) -lcairo

TEST_BINS = $(TEST_DIR)/test_toplevel $(TEST_DIR)/test_shm $(TEST_DIR)/test_render

tests: $(TEST_BINS)

$(TEST_DIR)/test_toplevel: $(TEST_DIR)/test_toplevel.cpp toplevel.cpp toplevel.h
	$(CXX) $(TEST_CXXFLAGS) -o $@ $(TEST_DIR)/test_toplevel.cpp toplevel.cpp $(TEST_LIBS)

$(TEST_DIR)/test_shm: $(TEST_DIR)/test_shm.cpp shm.c shm.h
	$(CXX) $(TEST_CXXFLAGS) -o $@ $(TEST_DIR)/test_shm.cpp shm.c $(TEST_LIBS)

$(TEST_DIR)/test_render: $(TEST_DIR)/test_render.cpp render.cpp render.h toplevel.h
	$(CXX) $(TEST_CXXFLAGS) -o $@ $(TEST_DIR)/test_render.cpp render.cpp toplevel.cpp $(TEST_LIBS)

test-run: tests
	@for t in $(TEST_BINS); do echo "=== Running $$t ==="; $$t; echo; done

clean:
	rm -f fltk-cpp-shell $(TEST_BINS) *.o

.PHONY: all clean run tests test-run
