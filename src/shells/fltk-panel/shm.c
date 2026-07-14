#include "shm.h"
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

int create_shm_fd(size_t size) {
  char name[] = "/tmp/wl_shm-XXXXXX";
  int fd = mkstemp(name);
  if (fd < 0) return -1;
  unlink(name);
  if (ftruncate(fd, (off_t)size) < 0) { close(fd); return -1; }
  return fd;
}
