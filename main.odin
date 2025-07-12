package main

import "core:log"
import "core:image"
import "core:image/bmp"
import "core:slice"
import "core:math"
import "core:io"
import "core:os"
import "core:fmt"
import "core:bytes"
import "core:flags"

// TODO: Use MINIAUDIO for audio decoding!!
// Or write your own library :)

main :: proc() {
    context.logger = log.create_console_logger()
    context.logger.options = { .Level, .Terminal_Color, .Line, .Procedure }

    hilbert, im_name, log_level := parse_args()
    context.logger.lowest_level = log_level

    if (im_name == "") { fmt.eprintln("No file specified to process"); os.exit(1) }

    // File error
    file, err_f := os.open(im_name)
    if err_f != nil {
        fmt.println("No such file")
        log.debug(err_f)
        log.debug(im_name)
        os.exit(1)
    }

    // Buffer the whole file
    file_size, _ := os.file_size(file)
    buffer := make([]u8, file_size)
    n, err_r := os.read_full(file, buffer)
    if err_r != nil { log.debug(err_r); return }
    os.close(file)

    // Prepare for parsing
    reader: bytes.Reader
    bytes.reader_init(&reader, buffer)
    p_err : io.Error = .None

    // https://docs.fileformat.com/audio/wav/
    riff: [4]u8; _, p_err = bytes.reader_read(&reader, riff[:])
    cksize: [4]u8; _, p_err = bytes.reader_read(&reader, cksize[:])
    waveid: [4]u8; _, p_err = bytes.reader_read(&reader, waveid[:])

    subchunk_id: [4]u8; _, p_err = bytes.reader_read(&reader, subchunk_id[:])
    chunk_size:  [4]u8; _, p_err = bytes.reader_read(&reader, chunk_size[:])
    wFormatTag:  [2]u8; _, p_err = bytes.reader_read(&reader, wFormatTag[:])
    nChannels:   [2]u8; _, p_err = bytes.reader_read(&reader, nChannels[:])
    nSamplesPerSec:  [4]u8; _, p_err = bytes.reader_read(&reader, nSamplesPerSec[:])
    nAvgBytesPerSec: [4]u8; _, p_err = bytes.reader_read(&reader, nAvgBytesPerSec[:])
    nBlockAlign:    [2]u8; _, p_err = bytes.reader_read(&reader, nBlockAlign[:])
    wBitsPerSample: [2]u8; _, p_err = bytes.reader_read(&reader, wBitsPerSample[:])
    subchunk2_id:   [4]u8; _, p_err = bytes.reader_read(&reader, subchunk2_id[:])
    subchunk2_size: [4]u8; _, p_err = bytes.reader_read(&reader, subchunk2_size[:])

    if waveid != "WAVE" { fmt.eprintfln("The file needs to be in WAV format"); os.exit(1) }

    // DEBUG ------------------------------------------------------------------
    log.debugf("riff: %s", riff)
    log.debugf("cksize: %v", slice_to_T(cksize[:], ^u32)^ + 4)
    log.debugf("waveid: %s", waveid)
    log.debugf("subchunk_id: %s", subchunk_id)
    log.debugf("chunk_size: %v", chunk_size)
    log.debugf("wFormatTag: %x", wFormatTag[:])
    log.debugf("nChannels: %v", slice_to_T(nChannels[:], ^u16)^)
    log.debugf("nSamplesPerSec: %v", slice_to_T(nSamplesPerSec[:], ^u32)^)
    log.debugf("nAvgBytesPerSec: %d", slice_to_T(nAvgBytesPerSec[:], ^u32)^)
    log.debugf("nBlockAlign: %d", slice_to_T(nBlockAlign[:], ^u16)^)
    log.debugf("wBitsPerSample: %d", slice_to_T(wBitsPerSample[:], ^u16)^)
    log.debugf("subchunk2_id: %d", slice_to_T(subchunk2_id[:], ^u16)^)
    log.debugf("subchunk2_id: %s", subchunk2_id[:])
    log.debugf("subchunk2_size: %d", slice_to_T(subchunk2_size[:], ^u16)^)
    // ------------------------------------------------------------------------

    // Weeee got the audio YAAAY
    pcm_audio := buffer[reader.i:len(reader.s)]

    square_side := cast(int)math.floor(math.sqrt_f32(cast(f32)len(pcm_audio) / 3))

    // DEBUG ------------------------------------------------------------------
    log.debug("")
    log.debugf("Audio len: %d", len(pcm_audio))
    log.debugf("Square side len: %d", square_side)
    log.debug("")
    // ------------------------------------------------------------------------

    side_power_2 := cast(int)math.ceil(math.log2(cast(f32)(square_side)))
    h_side := cast(int)math.pow2_f32(side_power_2)
    log.debug("log2 ceil of side:", h_side)
    log.debug("hilbert buffer len:", h_side * h_side)

    pixels_h: [][3]u8 = make([][3]u8, h_side * h_side)
    pixels:   [][3]u8 = make([][3]u8, square_side * square_side)

    if hilbert == true {
        for i in 0..<len(pcm_audio) {
            x, y := d2xy(side_power_2, i)
            pixels_h[x + (y * h_side)] = pcm_audio[i]
        }
    } else {
        for i in 0..<(square_side * square_side) {
            pixels[i][0] = pcm_audio[i * 3 + 0]
            pixels[i][1] = pcm_audio[i * 3 + 1]
            pixels[i][2] = pcm_audio[i * 3 + 2]
        }
    }



    if !hilbert {
        image_linear, ok_i_l := image.pixels_to_image(pixels[:], square_side, square_side)
        if !ok_i_l { log.debug("Fuck") }
        ok_f_l := bmp.save_to_file("./audio_linear.bmp", &image_linear)
        log.debug(ok_f_l)
    } else {
        image_hilbert, ok_i_h := image.pixels_to_image(pixels_h[:], h_side, h_side)
        if !ok_i_h { log.debug("Fuck 2 electric boogaloo") }
        ok_f_h := bmp.save_to_file("./audio_hilbert.bmp", &image_hilbert)
        log.debug(ok_f_h)
    }

}

// Very unsafe
slice_to_T :: #force_inline proc(slice: $S, $T: typeid) -> T {
    return (cast(T)(raw_data(slice[:])))
}

// PARSER ---------------------------------------------------------------------
// Simple state mashine
// For context: I'm drunk as fuck

PARSER_STATE :: enum {
    Undef,
    Raw,
    Arg_S,
    Arg_L,
    End,
}

HELP_MESSAGE :: `
-h --help      Prints help
-H --hilbert   Converts audio to a Hilbert curve
-L --linear    Converts audio to a linear representation
-D --debug     Show debug logs
`

// This (with some reflection) actually could be a very minimal library
parse_args :: proc() -> (hilbert: bool, im_name: string, log_level: log.Level ) {
    parser: PARSER_STATE = .Undef
    known_char: rune = ' '

    hilbert = false
    im_name = ""
    log_level = .Error

    for arg in os.args[1:] {
        // log.debug(arg)
        for c in arg {
            // log.debug(c)
            if parser == .Undef {
                if c == '-' { parser = .Arg_S; continue }
                else        { parser = .Raw;   continue }
            }

            if parser == .Arg_S { if c == '-' { parser = .Arg_L; continue } }

            // Because first assertion failed... (in a way)
            // My conception is that we should've'd a rune by now
            if parser == .Arg_S {
                // Handle this sh** manualy, I don't know man
                switch c {
                case 'h': { fmt.println(HELP_MESSAGE); os.exit(0) }
                case 'H': { hilbert = true }
                case 'L': { hilbert = false }
                case 'D': { log_level = .Debug }
                }
            }

            if parser == .Arg_L {
                switch arg[2:] {
                case "help":    { fmt.println(HELP_MESSAGE); os.exit(0) }
                case "hilbert": { hilbert = true }
                case "linear":  { hilbert = false }
                case "debug":   { log_level = .Debug }
                }
            }

            if parser == .Raw {
                im_name = arg
                break

                // You're in char loop dumbass
                // this will skip to next arg :)
                // No problem
            }
        }

        // Reset parser state
        parser = .Undef
    }

    return hilbert, im_name, log_level
}
