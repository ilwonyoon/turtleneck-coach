import SwiftUI

/// PT Turtle Design System — centralized design tokens.
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
