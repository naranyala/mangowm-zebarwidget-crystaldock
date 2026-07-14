#include <glib.h>
#include <string.h>
#include "../toplevel.h"

static void test_find_empty(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int dummy;
  g_assert_cmpint(toplevel_find(infos, count, &dummy), ==, -1);
}

static void test_find_not_found(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b;
  toplevel_add(infos, &count, &a);
  g_assert_cmpint(toplevel_find(infos, count, &b), ==, -1);
}

static void test_find_found(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b;
  toplevel_add(infos, &count, &a);
  toplevel_add(infos, &count, &b);
  g_assert_cmpint(toplevel_find(infos, count, &b), ==, 1);
}

static void test_add_basic(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b;

  int idx1 = toplevel_add(infos, &count, &a);
  g_assert_cmpint(idx1, ==, 0);
  g_assert_cmpint(count, ==, 1);
  g_assert(infos[0].handle == &a);

  int idx2 = toplevel_add(infos, &count, &b);
  g_assert_cmpint(idx2, ==, 1);
  g_assert_cmpint(count, ==, 2);
}

static void test_add_full(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  for (int i = 0; i < MAX_TOPLEVELS; i++) {
    int idx = toplevel_add(infos, &count, (void*)(intptr_t)(i + 1));
    g_assert_cmpint(idx, ==, i);
  }
  g_assert_cmpint(count, ==, MAX_TOPLEVELS);

  int r = toplevel_add(infos, &count, NULL);
  g_assert_cmpint(r, ==, -1);
  g_assert_cmpint(count, ==, MAX_TOPLEVELS);
}

static void test_remove_middle(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b, c;
  toplevel_add(infos, &count, &a);
  toplevel_add(infos, &count, &b);
  toplevel_add(infos, &count, &c);

  toplevel_remove_at(infos, &count, 1);
  g_assert_cmpint(count, ==, 2);
  g_assert(infos[0].handle == &a);
  g_assert(infos[1].handle == &c);
}

static void test_remove_first(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b;
  toplevel_add(infos, &count, &a);
  toplevel_add(infos, &count, &b);

  toplevel_remove_at(infos, &count, 0);
  g_assert_cmpint(count, ==, 1);
  g_assert(infos[0].handle == &b);
}

static void test_remove_last(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b;
  toplevel_add(infos, &count, &a);
  toplevel_add(infos, &count, &b);

  toplevel_remove_at(infos, &count, 1);
  g_assert_cmpint(count, ==, 1);
  g_assert(infos[0].handle == &a);
}

static void test_remove_invalid_negative(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  toplevel_add(infos, &count, (void*)1);
  toplevel_remove_at(infos, &count, -1);
  g_assert_cmpint(count, ==, 1);
}

static void test_remove_invalid_oob(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  toplevel_add(infos, &count, (void*)1);
  toplevel_remove_at(infos, &count, 5);
  g_assert_cmpint(count, ==, 1);
}

static void test_add_after_remove(void) {
  struct toplevel_info infos[MAX_TOPLEVELS];
  int count = 0;
  int a, b, c;
  toplevel_add(infos, &count, &a);
  toplevel_add(infos, &count, &b);
  toplevel_remove_at(infos, &count, 0);
  g_assert_cmpint(count, ==, 1);

  int idx = toplevel_add(infos, &count, &c);
  g_assert_cmpint(idx, ==, 1);
  g_assert_cmpint(count, ==, 2);
  g_assert(infos[1].handle == &c);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/toplevel/find/empty", test_find_empty);
  g_test_add_func("/toplevel/find/not_found", test_find_not_found);
  g_test_add_func("/toplevel/find/found", test_find_found);
  g_test_add_func("/toplevel/add/basic", test_add_basic);
  g_test_add_func("/toplevel/add/full", test_add_full);
  g_test_add_func("/toplevel/remove/middle", test_remove_middle);
  g_test_add_func("/toplevel/remove/first", test_remove_first);
  g_test_add_func("/toplevel/remove/last", test_remove_last);
  g_test_add_func("/toplevel/remove/invalid_negative", test_remove_invalid_negative);
  g_test_add_func("/toplevel/remove/invalid_oob", test_remove_invalid_oob);
  g_test_add_func("/toplevel/add_after_remove", test_add_after_remove);
  return g_test_run();
}
