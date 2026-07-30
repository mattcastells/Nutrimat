# Nutrimat

Nutrimat is an Android app for tracking food, activity, weight, water, and
sleep — built to show the full picture of a day instead of a single number,
and to never present an estimate as if it were a measurement.

## What it does

- **Meals** — search a catalog (Argentine foods, USDA, Open Food Facts by
  barcode), describe what you ate in plain text, or take a photo. AI estimates
  the items; you always review and confirm before anything is saved.
- **Activity** — MET-based calorie estimation with an adjustable exercise
  credit, plus manual entry for anything else.
- **Weight, body measurements, water, and sleep** — logged per day, editable
  and deletable at any time, for any date.
- **Progress** — trends over time, plus a full day-by-day history.
- **Pals** — share your day with people you choose. Meals and whether you
  moved are always visible to an accepted pal; photos, water, sleep, and
  exercise detail are each off by default and only shared if you turn them on.
- Automatic cloud backup, account sync across devices, and in-app
  self-updates (the app isn't distributed through the Play Store).

## Stack

Flutter (Android) · Supabase (Postgres with row-level security, Auth,
Storage, Edge Functions) · Gemini for photo/text meal analysis · USDA
FoodData Central and Open Food Facts for the food catalog.

## Status

Actively developed and in daily use. [`ESTADO.md`](./ESTADO.md) (Spanish)
tracks current state and what's next; [`docs/estado-de-la-app.md`](./docs/estado-de-la-app.md)
has the detailed feature-by-feature status.

## Running it

```bash
flutter pub get
flutter run                                        # local mode: no login, nothing leaves the device
flutter run --dart-define-from-file=env/local.json  # against a real Supabase project
flutter test
```

Without `env/local.json` the app runs entirely offline against local storage —
enough to clone the repo and run it, or run the test suite, with no
credentials at all.

## Legal

[`PRIVACY_POLICY.md`](./PRIVACY_POLICY.md) · [`TERMS_OF_SERVICE.md`](./TERMS_OF_SERVICE.md)
