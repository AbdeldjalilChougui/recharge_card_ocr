# Accuracy benchmark

Measures how well `recharge_card_ocr` reads codes with the real ML Kit
recogniser on an Android device or emulator. The full pipeline runs on the
device for every image: `CardCodeReader` (EXIF fix, zone crops, upscaling,
contrast) + `MlKitDigitReader` + `CodeExtractor`.

The same runner works on two kinds of input:

- **Synthetic cards** rendered by `generate.py` (made-up designs, random
  codes, controlled conditions such as blur, glare or EXIF rotation).
- **Your real card photos**, named after their code or listed in a CSV.

None of this is part of the published package (see `.pubignore`), and no
images are committed: generate them on demand.

## Files

| file | what it does |
|---|---|
| `generate.py` | renders the synthetic dataset and its `labels.json` |
| `run_on_device.dart` | host runner: installs the example app (debug), pushes the images, runs `integration_test/benchmark_test.dart`, pulls `results.json`, uninstalls the app |
| `report.py` | accuracy, CER, dangerous misses, false alarms, latency, per condition |
| `replay.dart` | re-runs only the text logic on the OCR output saved in a results file, to try extractor or threshold changes without the device |

## Requirements

- Flutter (the version the package supports) and an Android device or
  emulator visible to `adb`. Debug builds only: the runner uses `run-as`.
- `tar` on the host.
- Python 3. `report.py` needs only the standard library. `generate.py`
  needs Pillow (with libraqm for Arabic shaping) and NumPy:

  ```sh
  python3 -m venv /tmp/rco-venv
  /tmp/rco-venv/bin/pip install pillow numpy
  ```

- For `generate.py`, DejaVu, Liberation or Noto fonts (and a Noto Arabic
  font for the Arabic distractor text). The output is reproducible for a
  given seed, Pillow/NumPy version and set of installed fonts.

adb is found from `$ADB`, then `$ANDROID_HOME/platform-tools`, then `PATH`.

All commands below run from the `example/` directory.

## Run on your real card photos

1. Take 10 to 30 photos of scratched cards. Crop each photo to the card's
   edges (or take it with the example app, which crops to its frame). The
   zones of `ZoneLayout.rechargeCard` are relative to the card, so a photo
   with a lot of table around the card is read in the wrong place.
2. Put them in one folder, for example `build/benchmark/real/`, and name
   each file after its code: `12345678901234.jpg`. Non-digits such as
   dashes are dropped from the name, and anything after the first `_` is
   ignored, so two photos of the same card can be `12345678901234_1.jpg`
   and `12345678901234_2.jpg`. `.jpg`, `.jpeg` and `.png` are accepted.

   Or add a `labels.csv` in the same folder instead (then file names do not
   matter):

   ```csv
   file,code,serial,conditions
   IMG_0012.jpg,1234 5678 9012 34,000123456789,indoor;flash
   IMG_0013.jpg,98765432109876,,outdoor
   ```

   `serial` and `conditions` are optional (conditions are `;`-separated tags
   that get their own row in the report).
3. Start an emulator or plug in a phone, then run:

   ```sh
   dart run tool/benchmark/run_on_device.dart \
       --photos build/benchmark/real \
       --out build/benchmark/real_results.json \
       --device <adb device id> \
       --code-lengths 14,15,16
   python3 tool/benchmark/report.py build/benchmark/real_results.json --failures 30
   ```

   `--code-lengths` is the set of code lengths your app accepts (default:
   the lengths found in your labels). Add `--serial-lengths 12` if you
   labelled serials. The first run builds the example app, which takes a
   few minutes.

The report lists, per condition tag: exact-match accuracy, character error
rate, dangerous misses (a wrong code that was **not** flagged
`needsReview`), false alarms (a correct code that was flagged), and the
median and p95 time per photo. `--failures N` prints the first N failures
with the raw ML Kit text, which shows whether the zone missed the code, ML
Kit misread a digit, or the extractor picked the wrong candidate.

## Run on synthetic cards

```sh
/tmp/rco-venv/bin/python tool/benchmark/generate.py --out build/benchmark/synthetic
dart run tool/benchmark/run_on_device.dart \
    --dataset build/benchmark/synthetic \
    --out build/benchmark/results.json
python3 tool/benchmark/report.py build/benchmark/results.json
```

`generate.py --per-condition 20` (the default) writes 240 images: 20 per
condition among `clean`, `perspective`, `exif_rotation` (orientation tags 3,
6 and 8), `small_angle` (2 to 8 degrees), `gaussian_blur`, `motion_blur`,
`jpeg_low` (quality 8 to 25), `noise`, `lighting_glare`, `scratch_residue`,
`low_res` (320 to 480 px wide) and `mixed` (two or three of these at a
milder strength). Every card gets one of 15 code fonts in turn, a 14, 15 or
16-digit code in one of several groupings, a 12-digit serial, and
distracting text: "RECHARGE", Arabic text, a price such as "500 DA", a
validity date, a lot number and a barcode-like pattern. `labels.json`
records the truth and every parameter used.

## Compare settings in one run

`--config` takes a JSON file of variants. Each one runs over every image,
and the report prints one section per variant:

```json
{
  "variants": [
    {"name": "default"},
    {"name": "upscale-160", "prepare": {"minShortSide": 160}},
    {"name": "no-contrast", "prepare": {"contrastStretch": false}},
    {"name": "strict", "policy": {"minConfidence": 0.8}},
    {"name": "wide-code-zone", "layout": {"code": [0.05, 0.24, 0.95, 0.50]}}
  ]
}
```

`prepare` takes the `PrepareOptions` fields, `policy` the `ReviewPolicy`
fields, and `layout` replaces zones of `ZoneLayout.rechargeCard` with
`[left, top, right, bottom]` card-relative rectangles.

## Replay the text logic

```sh
dart run tool/benchmark/replay.dart build/benchmark/results.json build/benchmark/replayed.json
python3 tool/benchmark/report.py build/benchmark/replayed.json
```

This uses the OCR output stored in the results (boxes rounded to whole
pixels), so it only reflects changes to `CodeExtractor`, `DigitNormalizer`
and `ReviewPolicy`. Confirm any change with a new device run.
