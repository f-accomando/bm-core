/*
 * CRT scanline filter for Pi 1 (see crt.h).
 */
#include "crt.h"
#include "config.h"
#include "drivers/board.h"
#include "drivers/mmio.h"

#include <stdint.h>
#include <string.h>

int crt_mode(void)
{
    const char *v = config_get("video_crt");
    if (!v || !v[0]) {
        uint8_t m = board()->model;
        if (m == BOARD_ZERO || m == BOARD_ZERO_W || m == BOARD_ZERO_2W)
            return 1;
        return 2;
    }
    if (strcmp(v, "off") == 0 || strcmp(v, "1") == 0) return 1;
    if (strcmp(v, "rca") == 0 || strcmp(v, "2") == 0) return 2;
    if (strcmp(v, "hdmi") == 0 || strcmp(v, "3") == 0) return 3;
    if (strcmp(v, "on") == 0 || strcmp(v, "4") == 0) return 4;
    return 1;
}

const char *crt_choice(void)
{
    static const char *const names[] = { "", "1. Off", "2. RCA only", "3. HDMI only", "4. On (both)" };
    int m = crt_mode();
    return names[m >= 1 && m <= 4 ? m : 2];
}

static int video_is_hdmi(void)
{
    return !!(mmio_read(PERIPHERAL_BASE + 0x902000 + 0x0A0) & (1u << 16));
}

int crt_filter_is_active(void)
{
    if (!board_is_pi1())
        return 0;
    int m = crt_mode();
    if (m == 1) return 0;
    if (m == 4) return 1;
    int hdmi = video_is_hdmi();
    if (m == 2) return !hdmi;
    if (m == 3) return hdmi;
    return 0;
}

void crt_apply_filter(void *pixels, int w, int h, int pitch_bytes)
{
    if (!pixels || w <= 0 || h <= 0)
        return;
    for (int y = 1; y < h; y += 2) {
        uint32_t *row = (uint32_t *)((uint8_t *)pixels + y * pitch_bytes);
        int words = w / 2;
        for (int x = 0; x < words; x++) {
            uint32_t p = row[x];
            uint32_t half = (p >> 1) & 0x7BEF7BEFu;
            row[x] = half + ((half >> 1) & 0x7BEF7BEFu);
        }
    }
}
