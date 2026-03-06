# Privacy Policy

**Turtleneck Coach** — Posture Monitoring for macOS

*Last updated: March 4, 2026*

## Summary

Turtleneck Coach is a privacy-first posture monitoring app. All camera processing happens on your device. No images, video, or personal data are ever transmitted or stored remotely.

## Data Collection

### Camera Data

- Camera frames are processed **entirely on-device** using Apple's Vision framework.
- **No images or video are saved** to disk or transmitted over any network.
- Frames are analyzed in real time and immediately discarded after processing.

### Session Statistics

- The app stores **aggregate session statistics** locally on your Mac:
  - Session duration, average posture score, good posture percentage
  - Slouch event counts and correction counts
- Statistics are stored in `~/Library/Application Support/TurtleneckCoach/`.
- Session data is automatically pruned after **90 days**.

### Calibration Data

- A baseline posture angle (CVA) is stored in macOS UserDefaults.
- Calibration is performed locally each time you start the app.

## Data Sharing

- **No data is shared with third parties.**
- **No analytics, telemetry, or crash reporting** services are used.
- **No network connections** are made by the app (except the optional local-only MediaPipe server on a Unix socket).

## Data Export

- You can export your session data as a JSON file via Settings > Export Session Data.
- Export is **entirely user-initiated** — no automatic data collection occurs.
- Exported data contains session statistics only; no images or personal identifiers.

## Personal Information

- Turtleneck Coach does **not** collect any personally identifiable information (PII).
- No account creation, login, or registration is required.
- The optional feedback feature uses your default email client — the app does not collect or store your email address.

## Children's Privacy

This app does not knowingly collect data from children under 13.

## Changes to This Policy

We may update this policy from time to time. Changes will be posted on this page with an updated revision date.

## Contact

If you have questions about this privacy policy, please contact:

**Email:** ilwonyoon@gmail.com
