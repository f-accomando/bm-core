# bm-core - bare-metal kernel for Raspberry Pi Zero / Zero W (BCM2835)
# and Pi 1 (A, B, A+, B+). Pi Zero 2 W (BCM2710A1) builds as kernel7.img
# when ZERO2=1.

CROSS   ?= arm-none-eabi-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
QEMU    ?= qemu-system-arm
PYTHON  ?= python3

BUILD   := build
DIST    := dist
FW_DIR  := firmware

PORT    ?= /dev/ttyUSB0
BAUD    ?= 115200

VERSION := $(shell git describe --always --dirty 2>/dev/null || echo dev)
BRANCH  := $(or $(GITHUB_HEAD_REF),$(GITHUB_REF_NAME),$(shell git rev-parse --abbrev-ref HEAD 2>/dev/null),unknown)

ARCH    := -mcpu=arm1176jzf-s -marm -mfpu=vfp -mfloat-abi=hard
ARCH7   := -march=armv7ve -mtune=cortex-a53 -marm -mfpu=neon-vfpv4 -mfloat-abi=hard
SOC     :=
ZERO2   ?= 0
export ZERO2
K7      := $(if $(filter 1,$(ZERO2)),$(BUILD)/kernel7.img)

COMMON  = $(ARCH) $(SOC) -std=c11 -O2 -Wall -Wextra -g -Isrc -Ithird_party \
          -ffunction-sections -fdata-sections \
          -DUART_BAUD=$(BAUD)
CFLAGS  = $(COMMON) -D_DEFAULT_SOURCE -Ithird_party/lua \
          -Ithird_party/lwip/src/include -Isrc/net \
          -Ithird_party/mbedtls/include -DMBEDTLS_CONFIG_FILE='"bm_mbedtls.h"' $(WARN)

PI_O3_FILES ?=
ifneq ($(strip $(PI_O3_FILES)),)
$(patsubst %,$(BUILD)/k/%.o,$(PI_O3_FILES)): CFLAGS += -O3
endif

LCFLAGS := $(COMMON) -Os -ffreestanding -fno-builtin -fno-tree-loop-distribute-patterns
ASFLAGS = $(ARCH) $(SOC) -g -Isrc -Isrc/kernel -Wa,-I$(BUILD)
LDFLAGS = $(ARCH) -nostartfiles -Wl,--gc-sections
LDLIBS  := -Wl,--start-group -lc -lm -lgcc -Wl,--end-group
LLDLIBS := -nostdlib -lgcc

LUA_SRCS     := $(wildcard third_party/lua/*.c)
MBEDTLS_SRCS := $(wildcard third_party/mbedtls/library/*.c)
LWIP_SRCS    := $(wildcard third_party/lwip/src/core/*.c third_party/lwip/src/core/ipv4/*.c) \
                third_party/lwip/src/netif/ethernet.c third_party/lwip/src/apps/sntp/sntp.c
KERNEL_SRCS  := $(shell find src \( -name '*.c' -o -name '*.S' \) -print) $(LUA_SRCS) $(LWIP_SRCS) $(MBEDTLS_SRCS)
LOADER_SRCS  := $(wildcard chainloader/*.S chainloader/*.c) \
                src/drivers/uart.c src/drivers/gpio.c src/drivers/mbox.c \
                src/drivers/prop.c src/drivers/timer.c src/drivers/led.c src/drivers/board.c \
                src/arch/cache.c src/lib/crc32.c

KERNEL_OBJS  := $(patsubst %,$(BUILD)/k/%.o,$(KERNEL_SRCS))
KERNEL7_OBJS := $(patsubst %,$(BUILD)/k7/%.o,$(KERNEL_SRCS))
LOADER_OBJS  := $(patsubst %,$(BUILD)/l/%.o,$(LOADER_SRCS))
LUA_OBJS     := $(patsubst %,$(BUILD)/k/%.o,$(LUA_SRCS))
LWIP_OBJS    := $(patsubst %,$(BUILD)/k/%.o,$(LWIP_SRCS))
MBEDTLS_OBJS := $(patsubst %,$(BUILD)/k/%.o,$(MBEDTLS_SRCS))
THIRD7_OBJS  := $(patsubst %,$(BUILD)/k7/%.o,$(LUA_SRCS) $(LWIP_SRCS) $(MBEDTLS_SRCS))

$(BUILD)/k7/% $(BUILD)/kernel7.elf: ARCH := $(ARCH7)
$(BUILD)/k7/%: SOC := -DBM_ZERO2

VERSION_STAMP := $(BUILD)/version.txt
$(VERSION_STAMP): FORCE
	@mkdir -p $(dir $@)
	@echo '$(VERSION) $(BRANCH)' | cmp -s - $@ || echo '$(VERSION) $(BRANCH)' > $@
$(BUILD)/k/src/kernel/version.c.o $(BUILD)/k7/src/kernel/version.c.o: $(VERSION_STAMP)
$(BUILD)/k/src/kernel/version.c.o $(BUILD)/k7/src/kernel/version.c.o: CFLAGS += -DBM_VERSION=\"$(VERSION)\" \
    -DBM_BRANCH=\"$(BRANCH)\"
FORCE:

$(LUA_OBJS) $(LWIP_OBJS) $(MBEDTLS_OBJS) $(THIRD7_OBJS): WARN := -w

$(BUILD)/k/src/script/embed.S.o $(BUILD)/k7/src/script/embed.S.o: $(wildcard src/script/*.lua) keys/release-pub.pem

.DEFAULT_GOAL := all
.PHONY: FORCE all clean disasm firmware sdcard sdcard-chainloader image image-pi1 release install \
        run-serial qemu qemu7 qemu-screenshot

all: $(BUILD)/kernel.img $(K7) $(BUILD)/chainloader.img

$(BUILD)/k/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD)/l/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD)/k7/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD)/k/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/k7/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/l/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(LCFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/kernel.elf: $(KERNEL_OBJS) linker.ld
	$(CC) $(LDFLAGS) -T linker.ld -Wl,-Map=$(BUILD)/kernel.map $(KERNEL_OBJS) $(LDLIBS) -o $@

$(BUILD)/kernel7.elf: $(KERNEL7_OBJS) linker.ld
	$(CC) $(LDFLAGS) -T linker.ld -Wl,-Map=$(BUILD)/kernel7.map $(KERNEL7_OBJS) $(LDLIBS) -o $@

$(BUILD)/chainloader.elf: $(LOADER_OBJS) chainloader/linker.ld
	$(CC) $(LDFLAGS) -T chainloader/linker.ld -Wl,-Map=$(BUILD)/chainloader.map $(LOADER_OBJS) $(LLDLIBS) -o $@

$(BUILD)/%.img: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@
	@echo "$@: $$(stat -c %s $@) bytes"

disasm: $(BUILD)/kernel.elf $(BUILD)/chainloader.elf
	$(OBJDUMP) -d $(BUILD)/kernel.elf > $(BUILD)/kernel.lst
	$(OBJDUMP) -d $(BUILD)/chainloader.elf > $(BUILD)/chainloader.lst

firmware:
	./scripts/fetch-firmware.sh $(FW_DIR)

KERNEL   ?= kernel
SHIP_IMG := $(BUILD)/$(KERNEL).img
RADIO_FW := BCM43430A1.hcd brcmfmac43430-sdio.bin brcmfmac43430-sdio.txt brcmfmac43430-sdio.clm_blob \
            SYN43430A1.hcd SYN43430B0.hcd brcmfmac43436-sdio.bin brcmfmac43436-sdio.txt \
            brcmfmac43436-sdio.clm_blob brcmfmac43436s-sdio.bin brcmfmac43436s-sdio.txt

sdcard: $(SHIP_IMG) $(K7)
	@test -f $(FW_DIR)/start.elf || { echo "Run 'make firmware' first"; exit 1; }
	@mkdir -p $(DIST)/bm
	cp $(FW_DIR)/bootcode.bin $(FW_DIR)/start.elf $(FW_DIR)/fixup.dat $(DIST)/
	cp boot/config.txt $(DIST)/
	cp $(SHIP_IMG) $(DIST)/kernel.img
	$(if $(K7),cp $(K7) $(DIST)/kernel7.img,rm -f $(DIST)/kernel7.img)
	cp boot/ca.pem $(DIST)/bm/ca.pem
	@for f in $(RADIO_FW); do \
	    if [ -f $(FW_DIR)/$$f ]; then cp $(FW_DIR)/$$f $(DIST)/bm/ && \
	        echo "cp $$f -> $(DIST)/bm/"; fi; done
	@echo "Copy the contents of $(DIST)/ to the root of a FAT32 SD card."

IMAGE_FILES = $(FW_DIR)/bootcode.bin=bootcode.bin $(FW_DIR)/start.elf=start.elf \
              $(FW_DIR)/fixup.dat=fixup.dat boot/config.txt=config.txt \
              $(BUILD)/kernel.img=kernel.img boot/ca.pem=bm/ca.pem

image: $(BUILD)/kernel.img $(K7)
	@test -f $(FW_DIR)/start.elf || { echo "Run 'make firmware' first"; exit 1; }
	@mkdir -p $(DIST)
	$(PYTHON) scripts/mksd.py $(DIST)/bm-core.img --size-mib 64 --label BM $(IMAGE_FILES) \
	    $(if $(K7),$(K7)=kernel7.img) \
	    $(foreach f,$(RADIO_FW),$(if $(wildcard $(FW_DIR)/$(f)),$(FW_DIR)/$(f)=bm/$(f)))

image-pi1: $(BUILD)/kernel.img
	@test -f $(FW_DIR)/start.elf || { echo "Run 'make firmware' first"; exit 1; }
	@mkdir -p $(DIST)
	$(PYTHON) scripts/mksd.py $(DIST)/bm-core-pi1.img --size-mib 64 --label BM $(IMAGE_FILES)

RELEASE_DIR := $(DIST)/release
RELEASE_PUB ?= keys/release-pub.pem

release: $(BUILD)/kernel.img $(K7)
	rm -rf $(RELEASE_DIR)
	$(PYTHON) scripts/mkrelease.py $(RELEASE_DIR) --version $(VERSION) --commit $$(git rev-parse HEAD) \
	    --file $(BUILD)/kernel.img:/kernel.img $(if $(K7),--file $(K7):/kernel7.img) \
	    --file boot/ca.pem:/bm/ca.pem --pub $(RELEASE_PUB) $(RELEASE_FLAGS)

SD ?= /mnt/d
install: sdcard
	@test -d $(SD) || { echo "$(SD) is not mounted (sudo mount -t drvfs D: $(SD))"; exit 1; }
	@S=; [ -w $(SD) ] || S=sudo; \
	$$S mkdir -p $(SD)/bm && \
	$$S cp $(DIST)/bootcode.bin $(DIST)/start.elf $(DIST)/fixup.dat $(DIST)/config.txt $(DIST)/kernel.img \
	    $(if $(K7),$(DIST)/kernel7.img) $(SD)/ && \
	$$S cp $(DIST)/bm/* $(SD)/bm/ && \
	sync && echo "installed on $(SD): kernel $$(git describe --always --dirty)"

sdcard-chainloader:
	$(MAKE) sdcard KERNEL=chainloader

run-serial: $(BUILD)/kernel.img
	$(PYTHON) tools/bm_load.py --baud $(BAUD) $(PORT) $<

QEMU_ARGS := -M raspi0 -serial stdio -serial null

qemu: $(BUILD)/kernel.img
	$(QEMU) $(QEMU_ARGS) -bios $<

qemu7: $(BUILD)/kernel7.img
	$(QEMU) -M raspi2b -serial stdio -serial null -bios $<

qemu-screenshot: $(BUILD)/kernel.img
	./scripts/qemu-screenshot.sh $< $(BUILD)/screen.png

clean:
	rm -rf $(BUILD) $(DIST)

-include $(shell find $(BUILD) -name '*.d' 2>/dev/null)
