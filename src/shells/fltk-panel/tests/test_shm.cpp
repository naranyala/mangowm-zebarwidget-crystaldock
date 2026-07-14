#include <glib.h>
#include <unistd.h>
#include <sys/mman.h>
#include "../shm.h"

static void test_create_zero_size(void) {
  int fd = create_shm_fd(0);
  g_assert_cmpint(fd, >=, 0);
  close(fd);
}

static void test_create_small(void) {
  int fd = create_shm_fd(64);
  g_assert_cmpint(fd, >=, 0);

  // Verify we can mmap and write
  void *ptr = mmap(NULL, 64, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  g_assert(ptr != MAP_FAILED);
  memset(ptr, 0xAB, 64);
  g_assert_cmpint(((unsigned char*)ptr)[0], ==, 0xAB);
  g_assert_cmpint(((unsigned char*)ptr)[63], ==, 0xAB);
  munmap(ptr, 64);
  close(fd);
}

static void test_create_large(void) {
  size_t sz = 1024 * 1024; // 1MB
  int fd = create_shm_fd(sz);
  g_assert_cmpint(fd, >=, 0);

  void *ptr = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  g_assert(ptr != MAP_FAILED);

  // Write pattern and verify
  unsigned char *bytes = (unsigned char*)ptr;
  for (size_t i = 0; i < sz; i++)
    bytes[i] = (unsigned char)(i & 0xFF);
  g_assert_cmpint(bytes[0], ==, 0);
  g_assert_cmpint(bytes[255], ==, 255);
  g_assert_cmpint(bytes[256], ==, 0);

  munmap(ptr, sz);
  close(fd);
}

static void test_create_multiple(void) {
  int fd1 = create_shm_fd(16);
  int fd2 = create_shm_fd(16);
  g_assert(fd1 >= 0);
  g_assert(fd2 >= 0);
  g_assert_cmpint(fd1, !=, fd2);
  close(fd1);
  close(fd2);
}

static void test_create_panel_buffer(void) {
  // Simulate the panel buffer size: 1350x36 ARGB32
  int width = 1350, height = 36;
  int stride = width * 4;
  size_t size = (size_t)stride * (size_t)height;

  int fd = create_shm_fd(size);
  g_assert_cmpint(fd, >=, 0);

  off_t actual = lseek(fd, 0, SEEK_END);
  g_assert_cmpint(actual, ==, (off_t)size);

  close(fd);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, NULL);
  g_test_add_func("/shm/create/zero_size", test_create_zero_size);
  g_test_add_func("/shm/create/small", test_create_small);
  g_test_add_func("/shm/create/large", test_create_large);
  g_test_add_func("/shm/create/multiple", test_create_multiple);
  g_test_add_func("/shm/create/panel_buffer", test_create_panel_buffer);
  return g_test_run();
}
