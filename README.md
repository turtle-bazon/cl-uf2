# cl-uf2

Common Lisp command line converter between Microsoft [UF2](https://github.com/microsoft/uf2)
and raw binary (BIN) formats.

The executable is named `uf2` and exposes sub-commands:
`to-uf2`, `from-uf2` and `info`.

## Build

Requires SBCL with [Quicklisp](https://www.quicklisp.org/) installed.

```sh
make build       # produces build/uf2
make test        # runs the FiveAM test suite
make clean       # removes build/
```

`make build` runs `sbcl --non-interactive --load build.lisp`, which quickloads the
`cl-uf2` system and builds the executable with ASDF's `program-op`. `make test`
quickloads the `cl-uf2-tests` system and exits non-zero on any failure.

## Usage

```
uf2 to-uf2 [options] <INPUT> [<OUTPUT>]
uf2 from-uf2 [options] <INPUT> [<OUTPUT>]
uf2 info <INPUT>
```

- `to-uf2` converts a BIN file to UF2.
- `from-uf2` converts a UF2 file to BIN.
- `info` displays header information from a UF2 file.

### `to-uf2` options

| Option                | Description                                              |
|-----------------------|----------------------------------------------------------|
| `-f`, `--flags <v>`   | Set UF2 block flags, OR-ed together; default `0x0`.      |
| `-a`, `--address <v>` | Set target address; default `0x0`.                       |
| `-i`, `--identify <v>`| Set family ID (sets the `FAMILY_ID_PRESENT` flag); default `0x0`. |
| `-s`, `--size <v>`    | Set UF2 block payload size; default `256`, max `476`.    |
| `-F`, `--fixed`       | Keep the real payload size on the last (short) block.    |
| `-y`, `--force`       | Overwrite an existing output file without prompting.     |
| `-h`                  | Print usage messages.                                    |

### `from-uf2` options

| Option                | Description                                              |
|-----------------------|----------------------------------------------------------|
| `-y`, `--force`       | Overwrite an existing output file without prompting.     |
| `-h`                  | Print usage messages.                                    |

### `info` options

| Option       | Description                              |
|--------------|------------------------------------------|
| `--help`     | Display usage information and exit.      |

The `to-uf2`, `from-uf2` and `info` commands also accept `--help` and `--version`.

Numeric values follow `strtoul` base-0 rules: `0x`/`0X` prefix for hexadecimal,
a leading `0` for octal, otherwise decimal. Hex digits are case-insensitive.

If the output file already exists and `--force` is not given, you are prompted
for confirmation; declining (or end of input) aborts with exit code `255`.
Use `--force` for non-interactive use.

### Examples

```sh
uf2 to-uf2 firmware.bin firmware.uf2         # BIN -> UF2 (default address 0x0)
uf2 to-uf2 -a 0x2000 -i 0xADA52840 in.bin    # BIN -> UF2 with address and family ID
uf2 from-uf2 firmware.uf2 firmware.bin       # UF2 -> BIN
uf2 info firmware.uf2                        # show block header information
```

When `OUTPUT` is omitted, the name is derived from the input with a `.uf2` (for
`to-uf2`) or `.bin` (for `from-uf2`) extension; an input that already ends in
the target extension gets a doubled one (`.uf2.uf2`, `.bin.bin`).

### Exit codes

Errors are printed to stderr and the process exits with code `255`.

## UF2 format

Each UF2 file is a sequence of 512-byte self-contained blocks:

- 32-byte header: `magicStart0` (`0x0A324655`), `magicStart1` (`0x9E5D5157`),
  flags, target address, payload size, block number, block count, family ID
- payload data (up to 476 bytes, 256 by default, zero-padded)
- 4-byte trailer: `magicEnd` (`0x0AB16F30`)

All integers are little-endian. See the
[official specification](https://github.com/microsoft/uf2) for details.

## Project layout

- `src/uf2.lisp`   — format constants, little-endian helpers, block decode/encode
- `src/main.lisp`  — CLI: argument parsing, conversions, output handling
- `tests/`         — FiveAM test suite
- `build.lisp`     — ASDF `program-op` build driver
- `Makefile`       — build/test/clean targets

## License

GPL-3.0.
