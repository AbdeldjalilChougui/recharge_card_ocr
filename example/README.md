# recharge_card_ocr example

A camera screen that shows the `CardScanOverlay` guides over a live
preview, takes a photo and reads the code and serial zones with
`CardCodeReader` + `MlKitDigitReader`.

Run it on an Android (API 21+) or iOS (15.5+) device:

```sh
flutter run
```

Set the `DigitCodeSpec`s in `lib/main.dart` to the format of your cards.
