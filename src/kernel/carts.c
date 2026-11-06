/*
 * SD card initialization and .bm cartridge scanning/execution for bm-core.
 */
#include "carts.h"
#include "bmz_install.h"
#include "fiber.h"
#include "ledstate.h"
#include "bm/bm.h"
#include "bm/loading.h"
#include "bm/project.h"
#include "bm/runtime.h"
#include "drivers/sd.h"
#include "fs/fat.h"
#include "lib/printf.h"
#include "net/net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define MAX_CARTS 128

typedef struct {
    char dir[16];
    char name[32];
    char path[48];
    char title[48];
    uint32_t size;
    int is_bme;
} cart_entry_t;

static cart_entry_t carts[MAX_CARTS];
static int ncarts;
static int sd_ok;

static int sd_tick(void)
{
    loading_tick();
    fiber_slice();
    return fiber_cancelled();
}

static int has_ext(const char *name, const char *ext)
{
    size_t nl = strlen(name), el = strlen(ext);
    return nl > el && strcasecmp(name + nl - el, ext) == 0;
}

static void scan_dir(const char *dir)
{
    fat_dir_t d;
    fat_entry_t e;
    if (fat_opendir(&d, dir) != 0)
        return;
    while (fat_readdir(&d, &e) && ncarts < MAX_CARTS) {
        if (e.is_dir || e.size < BM_HEADER_SIZE)
            continue;
        int bme = has_ext(e.name, ".bme");
        if (!bme && !has_ext(e.name, ".bm"))
            continue;
        uint8_t head[512];
        if (fat_read_head(&e, head) != 0 || !bm_is_cart(head))
            continue;
        cart_entry_t *c = &carts[ncarts++];
        snprintf(c->dir, sizeof c->dir, "%s", dir);
        snprintf(c->name, sizeof c->name, "%s", e.name);
        if (strcmp(dir, "/") == 0)
            snprintf(c->path, sizeof c->path, "/%s", e.name);
        else
            snprintf(c->path, sizeof c->path, "%s/%s", dir, e.name);
        memcpy(c->title, head + 24, 47);
        c->title[47] = 0;
        if (!c->title[0])
            snprintf(c->title, sizeof c->title, "%s", e.name);
        c->size = e.size;
        c->is_bme = bme;
    }
}

static void rescan(void)
{
    ncarts = 0;
    if (!sd_ok)
        return;
    scan_dir("/");
    scan_dir("/bm");
    scan_dir(BM_PROJECTS_DIR);
}

void carts_init(void)
{
    sd_ok = 0;
    ncarts = 0;
    if (sd_init() != 0) {
        kprintf("sd: %s\n", sd_error());
    } else if (fat_mount() != 0) {
        kprintf("sd: %s card, %lu MB: %s\n", sd_is_hc() ? "SDHC" : "SD",
                sd_blocks() / 2048, fat_error());
    } else {
        sd_ok = 1;
        fat_set_clock(net_time);
    }
    ledstate_set(LED_NO_SD, !sd_ok);
    fat_load_tick = sd_tick;
    bm_parse_tick = sd_tick;
    if (!fat_write_tick)
        fat_write_tick = fiber_slice_tick;
    if (sd_ok)
        bmz_install_all(NULL);
    rescan();
    if (sd_ok) {
        char size[24], extra[48] = "";
        const uint32_t cb = fat_cluster_bytes();
        if (cb >= 1024)
            ksnprintf(size, sizeof size, "%lu KB", (unsigned long)(cb / 1024));
        else
            ksnprintf(size, sizeof size, "%lu bytes", (unsigned long)cb);
        uint32_t retries, timeouts;
        sd_counters(&retries, &timeouts);
        if (retries || timeouts)
            ksnprintf(extra, sizeof extra, "; %lu retried, %lu timed out",
                      (unsigned long)retries, (unsigned long)timeouts);
        kprintf("sd: %s card (%s), %s; %d cartridges; clusters %s%s\n",
                sd_is_hc() ? "SDHC" : "SD", sd_controller(), fat_describe(),
                ncarts, size, extra);
    }
}

int carts_count(void)
{
    return ncarts;
}

void carts_list(void)
{
    if (ncarts == 0) {
        kprintf("no cartridges on the SD card\n");
        return;
    }
    for (int i = 0; i < ncarts; i++) {
        const cart_entry_t *c = &carts[i];
        kprintf("  %2d  %-4s %7lu  %s  \"%s\"\n",
                i + 1, c->is_bme ? ".bme" : ".bm",
                (unsigned long)c->size, c->path, c->title);
    }
}

void carts_play_buffer(framebuffer_t *fb, const uint8_t *data, size_t len)
{
    if (len >= 8 && bm_is_cart(data)) {
        bm_stats_t st;
        bm_play(fb, data, len, 0, &st);
        bm_print_stats(&st);
    } else {
        kprintf("unknown cartridge format\n");
    }
}

static int lower_prefix(const char *s, const char *p, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        char a = s[i], b = p[i];
        if (a >= 'A' && a <= 'Z') a += 32;
        if (b >= 'A' && b <= 'Z') b += 32;
        if (a != b || !a)
            return 0;
    }
    return 1;
}

static int play_path(framebuffer_t *fb, const char *path)
{
    fat_entry_t e;
    uint8_t *data = NULL;
    size_t len = 0;
    if (fat_find(path, &e) != 0 || e.is_dir)
        return -1;
    if (fat_load(&e, &data, &len) != 0) {
        kprintf("\x1b[91mcannot read %s: %s\x1b[0m\n", path, fat_error());
        return -1;
    }
    carts_play_buffer(fb, data, len);
    free(data);
    return 0;
}

int carts_play_title(framebuffer_t *fb, const char *name)
{
    size_t n = strlen(name);
    if (!n)
        return -1;
    if (name[0] == '/' && play_path(fb, name) == 0)
        return 0;
    for (int i = 0; i < ncarts; i++) {
        const cart_entry_t *c = &carts[i];
        if (lower_prefix(c->title, name, n) || lower_prefix(c->name, name, n) ||
            strcasecmp(c->path, name) == 0)
            return play_path(fb, c->path);
    }
    return -1;
}
