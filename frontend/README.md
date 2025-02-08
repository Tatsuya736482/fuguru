# HOW TO RUN

Fill credentials in the following files:
- `/ios/Runner/GoogleService-Info.plist`
- `/lib/firebase_options.dart`
- `/android/app/google-services.json`
- `/firebase.json`






## Development

### Deploy to website
```bash
firebase deploy
```
### Deploy to iOS
```bash
flutter build ios && flutter build ipa
```

### Deploy to Android
```bash
flutter build appbundle
```

### Generate Icons
```bash
flutter pub run flutter_launcher_icons:main
```
