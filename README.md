# PCG/SNG -> SysEx Converter 

_For those who come after..._

This utility converts Korg PCG and SNG files into SysEx message files that can be sent to some vintage Korg
synthesizers. It's useful if you want to transfer data (e.g. after a data loss) to your synthesizer via MIDI instead of
using a floppy disk drive.

## Usage

```
./pcg2syx <input_file.pcg> [synth_model|n364]
```

## Supported synthesizers

- Korg N264/N364
- Korg X2/X3/X3R
- Korg 01/W, 03R/W


## Build

This small utility is written in Zig. To build it, you need to have Zig
[installed](https://ziglang.org/learn/getting-started/) on your system. Then, you can build the project using the
following command:

```sh
zig build --release=safe
```

## TODO

- [ ] Support SNG files
- [x] Add command-line options for input/output file paths
- [x] Add tests
- [ ] Add documentation
- [ ] Improve error handling and reporting

---

## Background

I'm the owner of a Korg N364 synthesizer, which is a great piece of hardware but has a limited interface for interacting
with the device via floppy disks and MIDI.

Korg provides factory data in the form of proprietary PCG (Program, Combination, Global) and SNG (Song) files that be
loaded into the synthesizer using the floppy drive (by design). In 2026, floppy disks aren't easy to find, also vintage
floppy drives tend to fail over time. Which leaves us with two options:

- Install a floppy drive emulator device (such as Gotek);
- Transfer data over MIDI using SysEx messages.

With regards to the floppy drive interface installed in N264/364, the ribbon cable is 26-pin, which is not compatible
with the 34-pin interface used by most floppy drive emulators. So one would also need to buy a 26-to-34 pin adapter,
which results in a higher cost. On top of it, disassembling the synth to access specifically the floppy drive connector
is not trivial.

As for the MIDI interface, it only requires a standard MIDI connection. There are many software tools available that
can send SysEx messages over MIDI, making it easy to transfer data to the synthesizer.

## Problem

To be able to send PCG/SNG data to the synthesizer over MIDI, we need to convert the PCG/SNG files into SysEx messages
first. There are some tools available, but they either do not support the N364 model, or are outdated and no longer
maintained. Some of them are closed-source and paid, which makes it difficult to verify their correctness or modify
them for our specific needs.

## Solution

This repository contains a solution that converts Korg PCG/SNG files into SysEx message files, that can be sent to
the Korg N364 using any compatible software (e.g. MIDI-OX, SysEx Librarian, etc.).

## Disclaimer

This project is not affiliated with or endorsed by Korg Inc. All trademarks and copyrights belong to their respective
owners. This project is for educational and personal use only. Please respect Korg's intellectual property rights and
do not distribute copyrighted material without permission.

Besides, use this software at your own risk. The author is not responsible for any damage or loss caused by using this
software.

## License

This project is licensed under the AGPL v3 License. See the LICENSE file for details.
