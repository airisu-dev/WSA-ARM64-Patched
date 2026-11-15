// Early-boot logger: forks a child that copies /dev/kmsg to the tail of small SCSI disks, then execs wsainit as PID 1.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define LOGSZ (1u << 20)
#define MAXDEV 8
static char buf[LOGSZ];
static size_t len;

static void app(const char *s, size_t n) { if (len + n < LOGSZ - 4096) { memcpy(buf + len, s, n); len += n; } }
static void appf(const char *fmt, ...) { char t[512]; __builtin_va_list a; __builtin_va_start(a, fmt); int n = vsnprintf(t, sizeof t, fmt, a); __builtin_va_end(a); if (n > 0) app(t, n < (int)sizeof t ? n : (int)sizeof t - 1); }

static void slurp(const char *p, char *out, size_t cap) { int f = open(p, O_RDONLY); out[0] = 0; if (f < 0) return; ssize_t n = read(f, out, cap - 1); close(f); if (n > 0) out[n] = 0; }

struct dev { int fd; off_t off; char name[16]; };
static char seen[32][16]; static int nseen;

int main(int argc, char **argv) {
  if (fork() != 0) { execv("/wsainit", argv); _exit(127); }
  unshare(CLONE_NEWNS);
  mkdir("/.dbg", 0755); mkdir("/.dbg/proc", 0755); mkdir("/.dbg/sys", 0755);
  mount("proc", "/.dbg/proc", "proc", 0, 0);
  mount("sysfs", "/.dbg/sys", "sysfs", 0, 0);
  mknod("/.dbg/kmsg", S_IFCHR | 0600, makedev(1, 11));
  int kf = open("/.dbg/kmsg", O_RDONLY | O_NONBLOCK);
  char t[256]; slurp("/.dbg/proc/cmdline", t, sizeof t);
  appf("WSALOG v1\ncmdline: %s\n", t);
  struct dev devs[MAXDEV]; int nd = 0; size_t flushed = (size_t)-1; int tick = 0;
  for (;;) {
    char rec[2048]; ssize_t n;
    while (kf >= 0 && (n = read(kf, rec, sizeof rec - 1)) != 0) {
      if (n < 0) { if (errno == EPIPE) continue; break; }
      rec[n] = 0; char *s = strchr(rec, ';'); app(s ? s + 1 : rec, strlen(s ? s + 1 : rec));
    }
    if ((tick++ % 5) == 0) {
      DIR *d = opendir("/.dbg/sys/block");
      for (struct dirent *e; d && (e = readdir(d));) {
        if (strncmp(e->d_name, "sd", 2) || strlen(e->d_name) > 8) continue;
        int known = 0; for (int i = 0; i < nseen; i++) if (!strcmp(seen[i], e->d_name)) known = 1;
        if (known || nd >= MAXDEV || nseen >= 32) continue;
        strncpy(seen[nseen++], e->d_name, 15);
        char p[128], v[64]; snprintf(p, sizeof p, "/.dbg/sys/block/%s/size", e->d_name); slurp(p, v, sizeof v);
        long long sz = atoll(v) * 512;
        snprintf(p, sizeof p, "/.dbg/sys/block/%s/dev", e->d_name); slurp(p, v, sizeof v);
        unsigned ma = 0, mi = 0; sscanf(v, "%u:%u", &ma, &mi);
        appf("[wsalog] disk %s size=%lld dev=%u:%u\n", e->d_name, sz, ma, mi);
        if (sz < (100ll << 30)) continue;
        snprintf(p, sizeof p, "/.dbg/%s", e->d_name); mknod(p, S_IFBLK | 0600, makedev(ma, mi));
        int fd = open(p, O_WRONLY); if (fd < 0) { appf("[wsalog] open %s failed: %s\n", p, strerror(errno)); continue; }
        devs[nd].fd = fd; devs[nd].off = sz - LOGSZ; strncpy(devs[nd].name, e->d_name, 15); nd++;
        appf("[wsalog] logging to %s\n", e->d_name);
      }
      if (d) closedir(d);
    }
    if (len != flushed && nd) {
      size_t w = (len + 4095) & ~4095u; memset(buf + len, 0, w + 4096 - len > LOGSZ - len ? LOGSZ - len : w + 4096 - len);
      size_t out = w + 4096 > LOGSZ ? LOGSZ : w + 4096;
      for (int i = 0; i < nd; i++) { if (pwrite(devs[i].fd, buf, out, devs[i].off) < 0) continue; fsync(devs[i].fd); }
      flushed = len;
    }
    usleep(50000);
  }
}
