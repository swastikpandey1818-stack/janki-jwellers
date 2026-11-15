# janki_jwellers

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Version 1.6 dashboard rate controls

The dashboard now includes manual gold/silver rate entry and an online spot-rate refresh. Rates are stored locally and included in version-2 JSON backups; version-1 backups remain importable. Online values are converted from USD/troy-ounce to INR/10g for gold and INR/g for silver using a USD/INR reference feed. These are indicative international spot references, not guaranteed local shop buy/sell rates; verify premiums, taxes, purity and local market quotes before issuing an invoice. The app retains the last saved rates if the network fetch fails.

The online rate fetch requires internet access on Android.
