# houseprintplus

Flutter printer plugin with Bluetooth connection and QR label printing support.

## Android Maven Source

Android artifacts are resolved from the GitHub repository-backed Maven path:

- `https://raw.githubusercontent.com/601652267/printMaven/main`

The repository is currently private, so Android builds need GitHub credentials.
Provide them in either of these ways:

```bash
export HOUSEPRINT_MAVEN_USER=your_github_username
export HOUSEPRINT_MAVEN_TOKEN=your_github_token
```

Or add them to the consuming app's `android/local.properties`:

```properties
houseprint.maven.user=your_github_username
houseprint.maven.token=your_github_token
```

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/developing-packages/),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
