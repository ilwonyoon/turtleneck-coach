# Privacy Policy

**Turtleneck Coach** — Posture Monitoring for macOS

*Last updated: March 6, 2026*

## Summary

Turtleneck Coach processes posture data on your Mac. The public DMG release does not create an account, does not send analytics, and does not upload camera frames or session data to a remote server.

## What the App Uses

### Camera

- The app uses your Mac camera to estimate posture in real time.
- Camera processing happens locally on your device.
- The app may use Apple's Vision framework and, when available, a local helper process for MediaPipe-based pose analysis.
- The helper process communicates only through a local Unix domain socket on your Mac. It is not a cloud service.

### Notifications

- If you allow notifications, the app can show posture reminders through macOS Notification Center.
- Notification preference and frequency settings are stored locally.

## What the App Stores Locally

### Calibration and Preferences

The app stores a small amount of local settings data in macOS UserDefaults, including:

- calibration baseline values
- camera/setup preferences
- sensitivity and notification settings
- some window and onboarding preferences

### Session Statistics

The app stores session summaries locally in:

- `~/Library/Application Support/TurtleneckCoach/`

Stored session data may include:

- session start and end time
- monitored duration
- average posture score
- good-posture percentage
- average CVA
- slouch, reset, and bad-posture summary counts

Session history is currently pruned after about 90 days.

## Camera Frames and Images

### Public DMG Release

- The public DMG release is intended to process camera frames in memory.
- It is not intended to save camera images or video during normal use.

### Development / Debug Builds

- Internal or debug builds may write temporary debug logs and labeled snapshot images to `/tmp` when diagnostic features are compiled in and used.
- These debug artifacts are for testing and are not part of normal public use.

## Data Sharing

- No camera frames, posture data, or session summaries are sent to our servers.
- No third-party analytics, ad SDKs, or crash-reporting services are included.
- The app does not require sign-in or an online account.

## Export and User-Initiated File Access

- You can export session summaries as a JSON file from Settings.
- Export happens only when you choose a destination in the standard macOS save panel.
- Exported files contain session statistics, not camera frames or video.

## Privacy Policy Link and Feedback

- The app includes a link to this privacy policy in Settings.
- If you use the feedback action, the app opens your default mail app with a draft email. Your message is handled by your mail provider, not by Turtleneck Coach.

## Children’s Privacy

Turtleneck Coach is not directed to children under 13, and we do not knowingly collect personal information from children.

## Changes to This Policy

We may update this policy from time to time. The latest version will be posted with an updated revision date.

## Contact

If you have questions about this privacy policy, please contact:

**Email:** ilwonyoon@gmail.com
