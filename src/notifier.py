"""macOS notification system for posture alerts."""

import subprocess
import time


class Notifier:
    """Sends macOS native notifications with cooldown to avoid spam."""

    def __init__(self, cooldown_seconds: float = 60.0):
        self._cooldown = cooldown_seconds
        self._last_notification_time: float = 0

    def notify(self, title: str, message: str) -> bool:
        """
        Send a macOS notification if cooldown has elapsed.
        Returns True if notification was sent.
        """
        now = time.time()
        if now - self._last_notification_time < self._cooldown:
            return False

        try:
            # Use osascript for reliable macOS notifications
            script = (
                f'display notification "{message}" '
                f'with title "{title}" '
                f'sound name "Blow"'
            )
            subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                timeout=5,
            )
            self._last_notification_time = now
            return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False

    def reset_cooldown(self):
        """Reset cooldown so next notification sends immediately."""
        self._last_notification_time = 0
