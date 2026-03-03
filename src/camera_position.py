"""Camera position configuration.

Handles different camera placements:
- CENTER: Laptop/webcam directly in front (default)
- LEFT: Laptop/camera to the left of the user
- RIGHT: Laptop/camera to the right of the user

Camera position affects which landmarks are most reliable for
turtle neck detection, since a side-angle camera can actually
see the forward head posture more clearly.
"""

from dataclasses import dataclass
from enum import Enum


class CameraPosition(Enum):
    CENTER = "center"
    LEFT = "left"
    RIGHT = "right"


@dataclass(frozen=True)
class CameraConfig:
    """Immutable camera configuration."""

    position: CameraPosition

    @property
    def is_side_view(self) -> bool:
        return self.position in (CameraPosition.LEFT, CameraPosition.RIGHT)

    @property
    def primary_side(self) -> str:
        """Which side of the body faces the camera more directly."""
        if self.position == CameraPosition.LEFT:
            return "right"  # user's right side faces left-placed camera
        elif self.position == CameraPosition.RIGHT:
            return "left"  # user's left side faces right-placed camera
        return "both"
