// Mark SELinux domains permissive in a binary (monolithic) policy file using libsepol.
// usage: sepermissive in out domain...   ("*" = every domain type)
#include <sepol/policydb/policydb.h>
#include <sepol/policydb/hashtab.h>
#include <sepol/policydb/ebitmap.h>
#include <sepol/policydb/services.h>
#include <sepol/handle.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int rd(const char *path, policydb_t *p) {
  FILE *f = fopen(path, "rb"); if (!f) { perror(path); return -1; }
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *b = malloc(n); if (fread(b, 1, n, f) != (size_t)n) return -1; fclose(f);
  struct policy_file pf; policy_file_init(&pf); pf.type = PF_USE_MEMORY; pf.data = b; pf.len = n;
  if (policydb_init(p)) return -1;
  return policydb_read(p, &pf, 0);
}

struct ctx { policydb_t *p; int count; };
static int mark_all(hashtab_key_t k, hashtab_datum_t d, void *arg) {
  struct ctx *c = arg; type_datum_t *t = d;
  if (t->flavor == TYPE_TYPE && !t->primary == 0) { /* real type, not alias/attribute */ }
  if (t->flavor == TYPE_TYPE) { if (ebitmap_set_bit(&c->p->permissive_map, t->s.value, 1) == 0) c->count++; }
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 4) { fprintf(stderr, "usage: %s in out domain...\n", argv[0]); return 2; }
  policydb_t p;
  if (rd(argv[1], &p)) { fprintf(stderr, "read failed\n"); return 1; }
  fprintf(stderr, "policy version %u, %u types\n", p.policyvers, p.p_types.nprim);
  struct ctx c = { &p, 0 };
  for (int i = 3; i < argc; i++) {
    if (!strcmp(argv[i], "*")) { hashtab_map(p.p_types.table, mark_all, &c); continue; }
    type_datum_t *t = hashtab_search(p.p_types.table, argv[i]);
    if (!t) { fprintf(stderr, "no type %s\n", argv[i]); return 1; }
    ebitmap_set_bit(&p.permissive_map, t->s.value, 1); c.count++;
  }
  fprintf(stderr, "marked %d permissive\n", c.count);
  void *buf; size_t len;
  struct policy_file pf; policy_file_init(&pf);
  if (policydb_to_image(NULL, &p, &buf, &len)) { /* older API fallback below */ }
  FILE *o = fopen(argv[2], "wb"); if (!o) { perror(argv[2]); return 1; }
  fwrite(buf, 1, len, o); fclose(o);
  fprintf(stderr, "wrote %zu bytes\n", len);
  return 0;
}
