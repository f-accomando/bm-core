# bm-core

Bare-metal kernel for Raspberry Pi Zero / Zero W / Pi 1 (BCM2835, ARM1176JZF-S) and Pi Zero 2 W (BCM2710A1).

## Features

- **Pure Text Boot & Shell (`bm>`)**: boots directly into the interactive terminal shell (HDMI console, UART serial, USB/Bluetooth keyboard, and network console).
- **Hardware Drivers**:
  - **GPU**: VideoCore IV V3D 3D & 2D hardware acceleration, QPU shaders, ETC1 textures, DMA.
  - **Wi-Fi**: CYW43438 / CYW43436 SDIO driver, WPA2, lwIP TCP/IP stack, DHCP, SNTP, mbedTLS (TLS 1.2 / HTTPS).
  - **Bluetooth**: HCI over UART, Classic + BLE + SMP pairing (gamepads, keyboards, mice).
  - **USB & Ethernet**: DWC2 host controller, USB HID (keyboards, mice, gamepads), SMSC95xx Ethernet.
  - **Audio**: HDMI IEC958 and PWM DMA audio with polyphonic synthesizer.
  - **Storage**: SD/SDHC (EMMC & SDHOST) and FAT16/FAT32 read/write filesystem.
- **Lua & `.bm` Cartridge Runtime**: built-in Lua 5.4 VM, REPL (`lua`), `/bm/autoexec.lua`, and full compatibility with `.bm` cartridges (`play`, `upload`, `bm_net.py --play`).

## Build

```sh
make -j$(nproc)
```

Produces `build/kernel.img` and `build/chainloader.img`. Run in QEMU:

```sh
make qemu
```
