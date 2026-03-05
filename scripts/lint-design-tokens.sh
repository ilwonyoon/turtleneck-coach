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
