/* The public key that checks the releases (src/net/release.c): PEM text, NUL-terminated. */
    .section .rodata
    .balign 4
    .globl bm_release_key
bm_release_key:
    .incbin "keys/release-pub.pem"
    .byte 0

/* Built-in Lua libraries for require() */
    .section .rodata
    .balign 4
    .globl bm_lib_bm3d, bm_lib_bm3d_end
bm_lib_bm3d:
    .incbin "src/script/bm3d.lua"
bm_lib_bm3d_end:

    .section .rodata
    .balign 4
    .globl bm_lib_bmlib, bm_lib_bmlib_end
bm_lib_bmlib:
    .incbin "src/script/bmlib.lua"
bm_lib_bmlib_end:

    .section .rodata
    .balign 4
    .globl bm_lib_bmnet, bm_lib_bmnet_end
bm_lib_bmnet:
    .incbin "src/script/bmnet.lua"
bm_lib_bmnet_end:

    .section .rodata
    .balign 4
    .globl bm_lib_riff, bm_lib_riff_end
bm_lib_riff:
    .incbin "src/script/riff.lua"
bm_lib_riff_end:

    .section .rodata
    .balign 4
    .globl bm_lib_bmui, bm_lib_bmui_end
bm_lib_bmui:
    .incbin "src/script/bmui.lua"
bm_lib_bmui_end:
