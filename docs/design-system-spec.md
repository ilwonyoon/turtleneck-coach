# Turtleneck Coach Design System — Codex Implementation Spec

## Overview

Replace all hardcoded design values across the Turtleneck Coach codebase with centralized `DS.*` design tokens. The app must look **identical** before and after — this is a pure refactor.

## Deliverables (in order)

1. Create `TurtleneckCoach/DesignSystem/DesignTokens.swift`
2. Add it to `build.sh` compile list
3. Migrate 7 view files + PostureEngine to use `DS.*` tokens
4. Create `scripts/lint-design-tokens.sh`
5. Add Design System section to `CLAUDE.md`

---

## Phase 1: DesignTokens.swift

Create `TurtleneckCoach/DesignSystem/DesignTokens.swift`:

```swift
import SwiftUI

/// Turtleneck Coach Design System — centralized design tokens.
/// All visual constants live here. Views reference `DS.*` instead of hardcoded values.
enum DS {

    // MARK: - Primitive Tokens

    /// Typography scale. All fonts use `.rounded` design where size is explicit.
    enum Font {
        /// 9pt — privacy footer, tiny labels
        static let micro     = SwiftUI.Font.system(size: 9, weight: .medium, design: .rounded)
        /// 10pt — badge text, small indicators
        static let mini      = SwiftUI.Font.system(size: 10, weight: .medium, design: .rounded)
        /// 11pt — menu bar label, section headers
        static let caption   = SwiftUI.Font.system(size: 11, weight: .medium, design: .rounded)
        /// 12pt — footnotes, secondary info
        static let footnote  = SwiftUI.Font.system(size: 12, weight: .medium, design: .rounded)
        /// 13pt — body text (macOS default)
        static let body      = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
        /// 14pt — feature icons, secondary scores
        static let callout   = SwiftUI.Font.system(size: 14, weight: .medium, design: .rounded)
        /// 16pt — score zone icons
        static let icon      = SwiftUI.Font.system(size: 16)
        /// SwiftUI .subheadline with medium weight
        static let subhead   = SwiftUI.Font.subheadline.weight(.medium)
        /// SwiftUI .subheadline with semibold weight
        static let subheadBold = SwiftUI.Font.subheadline.weight(.semibold)
        /// SwiftUI .headline
        static let headline  = SwiftUI.Font.headline
        /// SwiftUI .title3 with semibold weight — section titles
        static let title     = SwiftUI.Font.title3.weight(.semibold)
        /// SwiftUI .title2 with semibold weight — dashboard header
        static let titleLg   = SwiftUI.Font.title2.weight(.semibold)
        /// 22pt — emoji display in score ring
        static let emoji     = SwiftUI.Font.system(size: 22)
        /// 32pt bold rounded — large score number
        static let scoreLg   = SwiftUI.Font.system(size: 32, weight: .bold, design: .rounded)
        /// 44pt — success checkmark icon
        static let heroIcon  = SwiftUI.Font.system(size: 44)
        /// 56pt — onboarding tortoise icon
        static let display   = SwiftUI.Font.system(size: 56)
        /// 8pt — tiny badge icons
        static let badgeIcon = SwiftUI.Font.system(size: 8)
        /// 11pt monospaced — CVA debug overlay
        static let mono      = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
        /// SwiftUI .caption — system caption
        static let sysCaption = SwiftUI.Font.caption
        /// SwiftUI .caption2 — system caption2
        static let sysCaption2 = SwiftUI.Font.caption2
        /// SwiftUI .subheadline (no weight) — plain subheadline
        static let sysSubhead = SwiftUI.Font.subheadline
    }

    /// Spacing scale (4pt base, 2pt for micro-adjustments).
    enum Space {
        static let xxs: CGFloat = 1   // badge vertical
        static let xs:  CGFloat = 2   // tight spacing
        static let sm:  CGFloat = 4   // compact gaps
        static let md:  CGFloat = 8   // standard gap
        static let lg:  CGFloat = 12  // card padding, section spacing
        static let xl:  CGFloat = 16  // outer padding, major sections
        static let xxl: CGFloat = 20  // large section gaps
        static let xxxl: CGFloat = 24 // extra large
    }

    /// Corner radius scale.
    enum Radius {
        static let sm: CGFloat  = 4   // tiny accent bars
        static let md: CGFloat  = 8   // camera preview, small cards
        static let lg: CGFloat  = 10  // toast, zone cards
        static let xl: CGFloat  = 12  // main cards, material overlays
        static let xxl: CGFloat = 14  // dashboard cards
    }

    /// Raw color palette.
    enum Palette {
        static let green  = Color.green
        static let yellow = Color.yellow
        static let orange = Color.orange
        static let red    = Color.red
        static let blue   = Color.blue
        static let cyan   = Color.cyan
        static let mint   = Color.mint
    }

    // MARK: - Semantic Tokens

    /// Posture severity colors — used in PostureEngine, MenuBarView, scores.
    enum Severity {
        static let good       = Palette.green
        static let mild       = Palette.yellow
        static let moderate   = Palette.orange
        static let severe     = Palette.red
    }

    /// Surface materials for card backgrounds.
    enum Surface {
        static let card     = Material.regularMaterial
        static let overlay  = Material.thickMaterial
        static let subtle   = Material.ultraThinMaterial
    }

    /// Semantic font roles.
    enum Label {
        static let title    = Font.title
        static let body     = Font.subhead
        static let detail   = Font.footnote
        static let menuBar  = Font.caption
    }

    /// Standard component dimensions.
    enum Size {
        static let scoreRing: CGFloat = 56
        static let scoreStroke: CGFloat = 6
        static let statusDot: CGFloat = 10
        static let crosshair: CGFloat = 36
        static let headWidget: CGFloat = 40
        static let colorAccentBar: CGFloat = 4
        static let iconFrame: CGFloat = 24
        static let featureIconFrame: CGFloat = 20
    }
}
```

---

## Phase 2: Update build.sh

In `build.sh`, add the new file to the swiftc compilation list. Insert it BEFORE the existing Core files (around line 45):

```
  TurtleneckCoach/DesignSystem/DesignTokens.swift \
```

Insert this line right after line 44 (`swiftc \`) and before `TurtleneckCoach/Core/CalibrationManager.swift \`.

---

## Phase 3: Migrate View Files

### CRITICAL RULES:
- **Only replace values that map cleanly to a DS token**
- **Leave one-off values as-is** with `// DS: one-off` comment
- **Do NOT change any layout behavior** — the app must look identical
- **Materials**: Replace `.regularMaterial` with `DS.Surface.card`, `.thickMaterial` with `DS.Surface.overlay`, `.ultraThinMaterial` with `DS.Surface.subtle`
- **Colors passed as parameters** (like `scoreColor: Color`) should NOT be replaced — they're already dynamic

### File 1: PostureScoreView.swift (59 lines)

| Line | Current | Replace With |
|------|---------|-------------|
| 17 | `spacing: 14` | `spacing: 14` | `// DS: one-off` (not in scale) |
| 22 | `lineWidth: 6` | `lineWidth: DS.Size.scoreStroke` |
| 27 | `lineWidth: 6` | `lineWidth: DS.Size.scoreStroke` |
| 33 | `.font(.system(size: 22))` | `.font(DS.Font.emoji)` |
| 35 | `.frame(width: 56, height: 56)` | `.frame(width: DS.Size.scoreRing, height: DS.Size.scoreRing)` |
| 38 | `spacing: 2` | `spacing: DS.Space.xs` |
| 41 | `.font(.system(size: 32, weight: .bold, design: .rounded))` | `.font(DS.Font.scoreLg)` |
| 46 | `.font(.system(size: 14))` | `.font(DS.Font.callout)` |
| 50 | `.font(.subheadline)` | `.font(DS.Font.sysSubhead)` |

### File 2: CalibrationView.swift (57 lines)

| Line | Current | Replace With |
|------|---------|-------------|
| 10 | `spacing: 12` | `spacing: DS.Space.lg` |
| 12 | `.font(.headline)` | `.font(DS.Font.headline)` |
| 15 | `spacing: 4` | `spacing: DS.Space.sm` |
| 17 | `.font(.subheadline.weight(.semibold))` | `.font(DS.Font.subheadBold)` |
| 25 | `.padding(10)` | `.padding(10)` | `// DS: one-off` |
| 27 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 30 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 38 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 42 | `.padding(16)` | `.padding(DS.Space.xl)` |
| 43 | `.ultraThinMaterial` | `DS.Surface.subtle` |
| 44 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 48 | `spacing: 6` | `spacing: 6` | `// DS: one-off` |
| 50 | `.font(.caption2)` | `.font(DS.Font.sysCaption2)` |
| 53 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |

### File 3: CameraPreviewView.swift (234 lines)

This file has many one-off rendering values for the skeleton overlay. Only migrate the obvious tokens:

| Line | Current | Replace With |
|------|---------|-------------|
| 24 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |

All other values in this file (opacity gradients, line widths, dot sizes for skeleton rendering) are `// DS: one-off` — they are rendering-specific and don't belong in the design system.

### File 4: SettingsView.swift (195 lines)

Settings uses Form/macOS system styling. Most values are layout-specific:

| Line | Current | Replace With |
|------|---------|-------------|
| 192 | `.padding(20)` | `.padding(DS.Space.xxl)` |

Other values (form column widths, min window sizes) are `// DS: one-off` layout constraints.

### File 5: OnboardingView.swift (313 lines)

| Line | Current | Replace With |
|------|---------|-------------|
| 34 | `.padding(.horizontal, 16)` | `.padding(.horizontal, DS.Space.xl)` |
| 35 | `.padding(.vertical, 12)` | `.padding(.vertical, DS.Space.lg)` |
| 39 | `spacing: 16` | `spacing: DS.Space.xl` |
| 40 | `minLength: 16` | `minLength: DS.Space.xl` |
| 43 | `.font(.system(size: 56))` | `.font(DS.Font.display)` |
| 45 | `.foregroundStyle(.green)` | `.foregroundStyle(DS.Palette.green)` |
| 48 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 51 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 67 | `.padding(12)` | `.padding(DS.Space.lg)` |
| 69 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 71 | `minLength: 16` | `minLength: DS.Space.xl` |
| 81 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 94 | `.foregroundStyle(.orange)` | `.foregroundStyle(DS.Palette.orange)` |
| 96 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 102 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 105 | `.padding(12)` | `.padding(DS.Space.lg)` |
| 108 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 112 | `spacing: 14` | `spacing: 14` | `// DS: one-off` |
| 114 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 122 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 124 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 133 | `.thickMaterial` | `DS.Surface.overlay` |
| 134 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 138 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 140 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 143 | `.padding(12)` | `.padding(DS.Space.lg)` |
| 146 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 151 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 156 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 158 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 161 | `.padding(12)` | `.padding(DS.Space.lg)` |
| 163 | `.regularMaterial` | `DS.Surface.card` |
| 164 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 186 | `.font(.system(size: 44))` | `.font(DS.Font.heroIcon)` |
| 187 | `.foregroundStyle(.green)` | `.foregroundStyle(DS.Palette.green)` |
| 188 | `.padding(.top, 16)` | `.padding(.top, DS.Space.xl)` |
| 191 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 195 | `.font(.subheadline)` | `.font(DS.Font.sysSubhead)` |
| 223 | `.padding(.top, 16)` | `.padding(.top, DS.Space.xl)` |
| 230 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 235 | `.padding(.top, 20)` | `.padding(.top, DS.Space.xxl)` |
| 240 | `spacing: 12` | `spacing: DS.Space.lg` |
| 242 | `.fill(color.opacity(0.8))` | keep as-is (parameterized color) |
| 243 | `width: 4` | `width: DS.Size.colorAccentBar` |
| 246 | `.font(.system(size: 16))` | `.font(DS.Font.icon)` |
| 248 | `width: 24` | `width: DS.Size.iconFrame` |
| 253 | `.font(.subheadline.weight(.semibold))` | `.font(DS.Font.subheadBold)` |
| 255 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 263 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 269 | `.padding(.horizontal, 12)` | `.padding(.horizontal, DS.Space.lg)` |
| 270 | `.padding(.vertical, 10)` | `.padding(.vertical, 10)` | `// DS: one-off` |
| 271 | `.regularMaterial` | `DS.Surface.card` |
| 272 | `cornerRadius: 10` | `cornerRadius: DS.Radius.lg` |
| 276 | `spacing: 10` | `spacing: 10` | `// DS: one-off` |
| 278 | `.font(.system(size: 14))` | `.font(DS.Font.callout)` |
| 280 | `width: 20` | `width: DS.Size.featureIconFrame` |
| 285 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 287 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |

### File 6: DashboardView.swift (654 lines)

| Line | Current | Replace With |
|------|---------|-------------|
| 22 | `spacing: 16` | `spacing: DS.Space.xl` |
| 38 | `.padding(20)` | `.padding(DS.Space.xxl)` |
| 59 | `.font(.title2.weight(.semibold))` | `.font(DS.Font.titleLg)` |
| 73 | `spacing: 12` | `spacing: DS.Space.lg` |
| 76 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 83 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 89 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 94 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 100 | `spacing: 8` | `spacing: DS.Space.md` |
| 102 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 107 | `.padding(14)` | `.padding(14)` | `// DS: one-off` |
| 115 | `spacing: 12` | `spacing: DS.Space.lg` |
| 117 | `.font(.headline)` | `.font(DS.Font.headline)` |
| 213 | `.font(.headline)` | `.font(DS.Font.headline)` |
| 216 | `.font(.subheadline.weight(.semibold))` | `.font(DS.Font.subheadBold)` |
| 226 | `.padding(14)` | `.padding(14)` | `// DS: one-off` |
| 368 | `cornerRadius: 14` | `cornerRadius: DS.Radius.xxl` |

Chart colors (`.green`, `.orange`, `.red`, `.mint`) in DashboardView → replace with `DS.Palette.*` or `DS.Severity.*` where semantically appropriate:
- `Color.green.opacity(0.9)` for "good threshold" → `DS.Severity.good.opacity(0.9)`
- `Color.mint.opacity(0.9)` for "goal line" → `DS.Palette.mint.opacity(0.9)`
- `"Good": Color.green` → `"Good": DS.Severity.good`
- `"Bad": Color.orange` → `"Bad": DS.Severity.moderate`

### File 7: MenuBarView.swift (465 lines)

| Line | Current | Replace With |
|------|---------|-------------|
| 27 | `.padding(.horizontal, 16)` | `.padding(.horizontal, DS.Space.xl)` |
| 28 | `.padding(.top, 12)` | `.padding(.top, DS.Space.lg)` |
| 29 | `.padding(.bottom, 8)` | `.padding(.bottom, DS.Space.md)` |
| 34 | `spacing: 16` | `spacing: DS.Space.xl` |
| 49 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 62 | `.ultraThinMaterial` | `DS.Surface.subtle` |
| 95 | `.padding(12)` | `.padding(DS.Space.lg)` |
| 96 | `.thickMaterial` | `DS.Surface.overlay` |
| 97 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 103 | `.regularMaterial` | `DS.Surface.card` |
| 104 | `cornerRadius: 12` | `cornerRadius: DS.Radius.xl` |
| 111 | `.padding(16)` | `.padding(DS.Space.xl)` |
| 121 | `.padding(.horizontal, 16)` | `.padding(.horizontal, DS.Space.xl)` |
| 122 | `.padding(.vertical, 8)` | `.padding(.vertical, DS.Space.md)` |
| 155 | `.font(.system(size: 11, weight: .medium))` | `.font(DS.Font.caption)` |
| 171 | `.font(.title3.weight(.semibold))` | `.font(DS.Font.title)` |
| 196 | `.font(.system(size: 11, weight: .medium, design: .monospaced))` | `.font(DS.Font.mono)` |
| 198 | `.padding(.horizontal, 8)` | `.padding(.horizontal, DS.Space.md)` |
| 199 | `.padding(.vertical, 4)` | `.padding(.vertical, DS.Space.sm)` |
| 216 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 218 | `.padding(.horizontal, 16)` | `.padding(.horizontal, DS.Space.xl)` |
| 222 | `cornerRadius: 10` | `cornerRadius: DS.Radius.lg` |
| 221 | `.regularMaterial` | `DS.Surface.card` |
| 224 | `.padding(.horizontal, 16)` | `.padding(.horizontal, DS.Space.xl)` |
| 225 | `.padding(.top, 8)` | `.padding(.top, DS.Space.md)` |
| 237 | `.frame(width: 10, height: 10)` | `.frame(width: DS.Size.statusDot, height: DS.Size.statusDot)` |
| 241 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 243 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 299 | `spacing: 6` | `spacing: 6` | `// DS: one-off` |
| 318 | `.font(.system(size: 8))` | `.font(DS.Font.badgeIcon)` |
| 321 | `.font(.system(size: 10))` | `.font(DS.Font.mini)` |
| 324 | `.padding(.horizontal, 8)` | `.padding(.horizontal, DS.Space.md)` |
| 325 | `.padding(.vertical, 3)` | `.padding(.vertical, 3)` | `// DS: one-off` |
| 335 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 341 | `size: 36` | keep as-is (crosshair generator param) |
| 390 | `.font(.system(size: 10))` | `.font(DS.Font.mini)` |
| 399 | `.frame(height: 40)` | `.frame(height: DS.Size.headWidget)` |
| 413 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 425 | `.font(.subheadline.weight(.medium))` | `.font(DS.Font.subhead)` |
| 441 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |
| 445 | `.regularMaterial` | `DS.Surface.card` |
| 446 | `cornerRadius: 8` | `cornerRadius: DS.Radius.md` |
| 454 | `.font(.system(size: 9))` | `.font(DS.Font.micro)` |
| 460 | `.font(.caption)` | `.font(DS.Font.sysCaption)` |

### File 8: PostureEngine.swift — Color Consolidation

Replace hardcoded Color references with DS.Severity tokens:

**Lines 51-58 (postureScoreColor):**
```swift
var postureScoreColor: Color {
    let score = postureScore
    let mode = sensitivityMode
    if score >= mode.goodThreshold { return DS.Severity.good }
    if score >= mode.correctionThreshold { return DS.Severity.mild }
    if score >= mode.badThreshold { return DS.Severity.moderate }
    return DS.Severity.severe
}
```

**Lines 145-152 (menuBarSeverityColor):**
```swift
var menuBarSeverityColor: Color {
    switch menuBarSeverity {
    case .good: return DS.Severity.good
    case .correction: return DS.Severity.mild
    case .bad: return DS.Severity.moderate
    case .away: return DS.Severity.severe
    }
}
```

---

## Phase 4: Lint Script

Create `scripts/lint-design-tokens.sh`:

```bash
#!/bin/bash
# Turtleneck Coach Design Token Lint
# Scans view files for hardcoded values that should use DS.* tokens.
# Exit 0 = clean, Exit 1 = violations found.
set -euo pipefail

VIOLATIONS=0
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Files to scan (views + PostureEngine)
SCAN_FILES=(
    TurtleneckCoach/Views/PostureScoreView.swift
    TurtleneckCoach/Views/CalibrationView.swift
    TurtleneckCoach/Views/CameraPreviewView.swift
    TurtleneckCoach/Views/SettingsView.swift
    TurtleneckCoach/Views/OnboardingView.swift
    TurtleneckCoach/Views/DashboardView.swift
    TurtleneckCoach/Views/MenuBarView.swift
    TurtleneckCoach/Core/PostureEngine.swift
)

# Skip lines with "// DS: one-off" annotation
is_exempted() {
    echo "$1" | grep -q "// DS: one-off" && return 0
    return 1
}

check_pattern() {
    local pattern="$1"
    local description="$2"
    local file="$3"

    while IFS= read -r match; do
        [ -z "$match" ] && continue
        if ! is_exempted "$match"; then
            echo -e "${RED}VIOLATION${NC} [$description] in $file:"
            echo "  $match"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < <(grep -n "$pattern" "$file" 2>/dev/null || true)
}

echo "Turtleneck Coach Design Token Lint"
echo "==========================="
echo ""

for file in "${SCAN_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}SKIP${NC} $file (not found)"
        continue
    fi

    # 1. Hardcoded font sizes: .system(size: N) — should use DS.Font.*
    check_pattern '\.system(size:' "Hardcoded font size" "$file"

    # 2. Raw SwiftUI font modifiers: .font(.caption), .font(.headline), etc.
    #    Should use DS.Font.sysCaption, DS.Font.headline, etc.
    check_pattern '\.font(\.caption[^2])' "Raw .caption font" "$file"
    check_pattern '\.font(\.caption2)' "Raw .caption2 font" "$file"
    check_pattern '\.font(\.headline)' "Raw .headline font" "$file"
    check_pattern '\.font(\.subheadline' "Raw .subheadline font" "$file"
    check_pattern '\.font(\.title' "Raw .title font" "$file"

    # 3. Raw Color references: Color.green, .green (in foregroundStyle/Color context)
    #    Skip DS.Palette/DS.Severity references and parameterized colors
    check_pattern 'return \.green\b' "Raw Color.green" "$file"
    check_pattern 'return \.yellow\b' "Raw Color.yellow" "$file"
    check_pattern 'return \.orange\b' "Raw Color.orange" "$file"
    check_pattern 'return \.red\b' "Raw Color.red" "$file"

    # 4. Hardcoded corner radii: cornerRadius: <number>
    check_pattern 'cornerRadius: [0-9]' "Hardcoded cornerRadius" "$file"

    # 5. Raw material references
    check_pattern '\.regularMaterial\b' "Raw .regularMaterial" "$file"
    check_pattern '\.thickMaterial\b' "Raw .thickMaterial" "$file"
    check_pattern '\.ultraThinMaterial\b' "Raw .ultraThinMaterial" "$file"
done

echo ""
if [ $VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}PASS${NC} No design token violations found."
    exit 0
else
    echo -e "${RED}FAIL${NC} Found $VIOLATIONS violation(s). Use DS.* tokens or add '// DS: one-off' to exempt."
    exit 1
fi
```

Make it executable: `chmod +x scripts/lint-design-tokens.sh`

---

## Phase 5: Update CLAUDE.md

Add this section after the "Frameworks" section:

```markdown
## Design System

All visual constants live in `TurtleneckCoach/DesignSystem/DesignTokens.swift` under the `DS` namespace.

- **Primitive tokens**: `DS.Font`, `DS.Space`, `DS.Radius`, `DS.Palette` — raw values
- **Semantic tokens**: `DS.Severity`, `DS.Surface`, `DS.Label`, `DS.Size` — intent-based
- **Lint**: `./scripts/lint-design-tokens.sh` — catches hardcoded fonts, colors, radii, materials in view files
- **One-offs**: Mark with `// DS: one-off` comment to suppress lint warnings
- **Rule**: New views MUST use `DS.*` tokens. No raw font sizes, colors, or spacing in view files.
```

---

## Verification Checklist

After all changes:

1. `./build.sh` — must compile with zero errors
2. `./scripts/lint-design-tokens.sh` — must exit 0
3. `grep -rn "\.system(size:" TurtleneckCoach/Views/` — must return 0 results
4. App must look visually identical — no layout or color changes
