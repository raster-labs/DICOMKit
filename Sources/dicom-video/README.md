# dicom-video

Convert H.264/AVC, H.265/HEVC and MPEG-2 video to and from DICOM Video IODs.

`dicom-video` **remuxes**: it rewraps an already-conformant bitstream without
re-encoding it. This is lossless and fast. Non-conformant input is rejected with
the specific violated constraint and a copy-pasteable remedy, never silently
re-encoded — re-encoding degrades diagnostic pixel data on every pass.

`dicom-image` is the still-image counterpart; image sequences belong there.

## Commands

```
dicom-video convert <input> --output <out.dcm>
dicom-video batch   <input-dir> --output-dir <dir>
dicom-video extract <in.dcm> --output <out.mp4>
dicom-video probe   <input>
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | I/O or usage error |
| `2`  | Conformance rejection — the input is readable but not DICOM-legal |

The split lets scripts tell "broken" from "not DICOM-legal".

## convert

```bash
dicom-video convert clip.mp4 --output clip.dcm \
    --patient-name "Doe^Jane" --patient-id MRN-1
```

The transfer syntax is detected from the bitstream: the first one the stream
actually validates against wins, so the choice is always one `probe` agrees with.

| Stream | Transfer syntax |
|---|---|
| MPEG-2 Main Profile, Main or Low Level | `…4.100` |
| MPEG-2 Main Profile, High Level (1280x720 / 1920x1080, 16:9) | `…4.101` |
| H.264 High, fits Level 4.1 | `…4.102` |
| H.264 High, needs Level 4.2 (e.g. 1080p60) | `…4.104` |
| H.264 High with a frame packing SEI (3D) | `…4.105` |
| H.264 MVC with a Stereo High subset SPS | `…4.106` |
| HEVC Main, Level ≤ 5.1, Main tier (8-bit, up to 4K60) | `…4.107` |
| HEVC Main 10, Level ≤ 5.1, Main tier (10-bit, up to 4K60) | `…4.108` |

BD-compatible `…4.103` is used only when named with `--transfer-syntax`, since
it adds constraints without adding capability. A payload larger than one 32-bit
fragment (about 4 GiB) moves MPEG-2 and H.264 to their fragmentable `….1` twin;
the HEVC transfer syntaxes are fragmentable already and have no `….1` twin.

Rows, Columns, Number of Frames, frame rate and bit depth are all read from the
bitstream, so the attributes cannot contradict the pixel data. Stereo Pairs
Present (0022,0028) is written YES for `…4.105` and `…4.106` (PS3.5 Table 8-8),
and the Basic Offset Table is written empty.

Useful flags:

- `--type endoscopic|microscopic|photographic` — selects the SOP class. Defaults
  to `endoscopic` (modality `ES`) and prints a notice when it does, because a
  wrong guess yields a valid but mislabelled object.
- `--dry-run` — probe and validate, write nothing.
- `--transfer-syntax <uid>` — override detection. The override is still
  validated; a mislabelled object is worse than a rejected one.
- `--frame-rate <fps>` — override the probed rate, then validate against it.
- `--trust-input` — encapsulate an MPEG-TS payload without validating it.
  Transport streams are demultiplexed and validated by default (PAT/PMT, the
  video PID's parameter sets and pictures, PES timestamps for the frame rate,
  and the audio PIDs); this flag skips that, so it requires an explicit
  `--transfer-syntax`.
- `--modality`, `--patient-sex`, `--patient-birth-date` — a value the IOD does
  not allow is refused: the command exits 1 and writes nothing. Modality
  (0008,0060) shall be `ES`, `GM` or `XC` for `--type endoscopic`, `microscopic`
  or `photographic` (PS3.3 A.32.5.4.1, A.32.6.4.1, A.32.7.4.1); Patient's Sex is
  `M`, `F` or `O` (PS3.3 Table C.7-1); a birth date must be DA (`YYYYMMDD`,
  PS3.5 Table 6.2-1). `--transfer-syntax 1.2.840.10008.1.2.4.107.1` / `.108.1`
  ("Fragmentable HEVC") is refused too: PS3.6 Table A-1 does not register them.
  (Until 2026-10-01 these were written with a warning.)
- `--audio-channel-source <keyword|SCHEME:VALUE[:MEANING]>` — the PS3.16 CID 3000
  source of the multiplexed audio, written in (003A,0300) (PS3.3 Table C.7-13).
  Given once, it applies to every audio track. Repeat it to give one source per
  audio track, in container order: each (003A,0300) Item has its own Channel
  Source Sequence (003A,0208). A count that matches neither 1 nor the number of
  tracks exits 1.
- `-v, --verbose` — explain each step: the container recognised, why that
  transfer syntax was chosen, where the frame count came from, the UIDs minted
  and how many bytes of the output are payload rather than DICOM overhead.

## Verbose

`-v` / `--verbose` is available on all four subcommands. It answers "why did it
decide that?" without a second run under a debugger:

```console
$ dicom-video convert clip.mp4 --output clip.dcm --verbose
verbose: read 376 bytes; container detected as MP4
verbose: transfer syntax 1.2.840.10008.1.2.4.102 selected from the bitstream's codec, profile and level
verbose: validated the stream against MPEG-4 AVC/H.264 HP @ Level 4.1: conformant
verbose: frame count 300 from sampleTable
verbose: SOP class Video Endoscopic Image Storage
verbose: Study Instance UID  1.2.276.0.7230010.3.1…  (generated)
verbose: encoded 1394 bytes: 376 bytes of bitstream carried unchanged, 1018 bytes of DICOM overhead
Wrote clip.dcm
```

Every verbose line is prefixed `verbose:` and written to **stderr**, so stdout
stays byte-for-byte what a non-verbose run prints and redirection keeps working:

```bash
dicom-video probe clip.mp4 --verbose > report.txt   # report.txt holds only the report
dicom-video batch clips/ --output-dir out/ -v 2>/dev/null   # just the converted list
```

It also explains rejections, which is where it earns its keep — the commentary
gathered before the failure is printed ahead of it, so a rejected clip still
says which container was read. Verbose never changes a message or an exit code.

## Audio

Audio interleaved in the container travels inside the encapsulated bit stream,
which PS3.5 permits, so `convert` carries it and says so:

```console
note: carrying 1 audio track (AAC, 48 kHz, 2 ch, 128 kbps) inside the encapsulated bit stream, as PS3.5 8.2.5 and 8.2.12 permit.
```

Each track is checked first. With H.264 or HEVC video (PS3.5 8.2.12):

| Format | Container | Sampling | Channels | Max bit rate |
|---|---|---|---|---|
| LPCM (16/20/24-bit) | MPEG-TS only | 48 or 96 kHz | 2 | 4.608 Mbps |
| AC-3 | MPEG-TS only | 48 kHz | 2 or 5.1 | 640 kbps |
| AAC | MPEG-TS or MP4 | 48 kHz | 2 or 5.1 | 640 kbps |
| MP3 (CBR) | MPEG-TS or MP4 | 32, 44.1 or 48 kHz | mono or stereo | 320 kbps |
| MPEG-1 Layer II | MPEG-TS or MP4 | 32, 44.1 or 48 kHz | 2 | 384 kbps |

With MPEG-2 video only CBR MP3 is permitted (PS3.5 8.2.5). A track that breaks
these rules is rejected with a remedy that re-encodes only the audio, copying
the video bit-for-bit, or drops it:

```
ffmpeg -i input.mp4 -map 0:v:0 -map 0:a -c:v copy -c:a aac -ar 48000 -ac 2 -b:a 192k fixed.mp4
```

## Rotation

Phones store portrait clips as landscape pixels plus a display rotation in the
container. DICOM has no attribute for that, so a DICOM viewer shows the clip
sideways. `probe` and `convert` report the rotation and warn; re-encoding with
ffmpeg applies it.

## batch

```bash
dicom-video batch clips/ --output-dir out/ --patient-name "Doe^Jane"
```

Clips convert in natural-sort order, so `clip2` precedes `clip10`.

`--series-mode single` (the default) puts every clip in one series. IHE
Endoscopy Image Archiving §3.10.4.1.1.1 makes this correct rather than merely
convenient: one procedure step on one piece of equipment is one series, and that
holds even when the endoscope is swapped mid-procedure.

`--series-mode per-file` gives each clip its own series, for clips from
different procedure steps or different equipment, where IHE *requires* separate
series. Combining it with `--series-uid` is rejected as contradictory.

Failure is fail-fast by default, so a half-populated series is never left
behind. `--continue-on-error` converts what it can, prints a summary and exits
`2`; skipped clips leave no gaps in `InstanceNumber`.

`--verbose` reports the grouping and the series/instance number each clip
received, which is what to check when a series comes out wrong.

## extract

```bash
dicom-video extract clip.dcm --output clip.mp4
```

Returns the encapsulated bitstream byte-for-byte. The payload keeps the
container it was encapsulated with, so an MP4 comes back an MP4; the suggested
extension follows the payload's own bytes.

## probe

```bash
dicom-video probe clip.mp4
```

Reports container, codec, profile, level, resolution, chroma, bit depth, frame
rate, frame count and the transfer syntax that fits — then the conformance
verdict. Exits `2` when the stream is not DICOM-legal, so `probe` answers "why
was this rejected?" without producing an object.

## What gets rejected, and why

Video DICOM is unusually strict. Each of these names the observed value, the
expected value and a remedy:

- **Profile** must match exactly. H.264 Baseline and Main are rejected.
- **Level** must not exceed the transfer syntax ceiling — and the picture must
  actually fit it. Picture size and throughput are checked against H.264 Table
  A-1 / H.265 Table A.8, so a 4K stream that merely *signals* Level 4.1 is
  rejected. An H.264 stream too large for Level 4.2 is pointed at HEVC (to keep
  the resolution) or at an orientation-aware scale to 1920x1080 / 1080x1920.
- **HEVC tier** must be Main (PS3.5 §8.2.10–8.2.11).
- **MPEG-2 pictures** must fit PS3.5 Table 8-1 for Main Level (720x576 at
  25 Hz, 720x480 at 30 Hz) and §8.2.6 for High Level (1280x720 or 1920x1080,
  16:9, Table 8-2 frame rates, no 1080p50/60).
- **Frame packing**: `…4.105` requires a frame packing arrangement SEI and
  `…4.104` forbids one (PS3.5 Table 8-8).
- **Audio** must meet PS3.5 §8.2.12 / §8.2.5 (see *Audio* above).
- **Chroma** must be 4:2:0. 4:2:2 and 4:4:4 are rejected.
- **Bit depth** must be 8 or 10, and must match the transfer syntax.
- **Pixels must be square.** DICOM cannot express anamorphic video, because
  Pixel Aspect Ratio (0028,0034) must be absent (PS3.5 §8.2.7).
- **Container** must be MP4 or MPEG-TS (PS3.5 §8.2.7–8.2.11). A `.mov` is not MP4.
  For MPEG2 (§8.2.5, §8.2.6) the standard leaves the container unconstrained, but
  this tool still requires MP4 or MPEG-TS.
  The remedy for a `.mov` rewraps it without re-encoding.
- **Size**: a non-fragmentable transfer syntax holds the whole bit stream in
  one fragment, so a payload over 4 GiB needs the `….1` variant.
- **BD-compatible** (`…4.103`) additionally requires a resolution and frame-rate
  combination from PS3.5 Table 8-4.

## Also in DICOMStudio

Everything above — the planning, the validation, the batch orchestration and
every line of console text — lives in `VideoWorkflow` and `VideoConsole` in
`DICOMKit/Video`. This file's `main.swift` is a thin ArgumentParser adapter over
them, and DICOMStudio's **CLI Workshop** is a second adapter over the same two
types, so the terminal and the app cannot drift. `VideoConsoleParityTests` pins
that.

The Studio **viewer** plays these objects directly: a video instance carries an
*image* SOP Class, so the transfer syntax is what identifies it, and the
extracted bit stream — the same passthrough `extract` performs — is handed to a
player, driven by the viewer's cine transport.

## References

- PS3.5 §8.2.5–8.2.11 — video encoding constraints, Tables 8-1 to 8-8; §8.2.12 — audio
- PS3.5 §8.2.12 — audio in AVC and HEVC bit streams
- PS3.6 Table A-1 — the video transfer syntax UIDs
- ITU-T H.264 Table A-1, ITU-T H.265 Table A.8 — level limits
- PS3.5 §A.4 — encapsulation of encoded pixel data
- PS3.6 Table A-1 — the 16 MPEG2 / MPEG-4 AVC/H.264 / HEVC/H.265 transfer syntaxes
- PS3.3 §A.32.5, §A.32.6, §A.32.7 — Video Endoscopic, Microscopic and Photographic Image IODs
- PS3.3 Table C.7-13 — Cine Module (Frame Time, Cine Rate, Recommended Display Frame Rate)
- IHE Endoscopy Image Archiving (EIA) Rev. 1.1 §3.10.4.1.1.1 — series grouping
