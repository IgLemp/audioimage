package main

import "core:slice"
import "core:fmt"
import "core:log"
import "core:image"
import "core:image/bmp"

SQUARE :: 16

make_image :: proc() {
    pixels: [SQUARE * SQUARE][3]u8 = {}
    slice.fill(pixels[:], 0)
        for i in 0..<SQUARE {
        for j in 0..<SQUARE {
            // m := j if j % 2 == 0 else 0
            // n := i if i % 2 == 0 else 0
            m := j
            n := i
            pixels[m + (n * SQUARE)] = {255, 255, 255}
        }
    }

    image, ok_i := image.pixels_to_image(pixels[:], SQUARE, SQUARE)
    if !ok_i { log.debug("Fuck") }
    ok_f := bmp.save_to_file("./image.bmp", &image)
    log.debug(ok_f)
}
