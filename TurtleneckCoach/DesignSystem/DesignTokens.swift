import SwiftUI

/// Turtleneck Coach Design System — centralized design tokens.
/// All visual constants live here. Views reference `DS.*` instead of hardcoded values.
///
/// Typography uses SwiftUI semantic text styles (SF Pro default).
/// `.rounded` design is reserved for the score display only.
/// Spacing follows an 8pt grid with 4pt half-unit minimum.
/// Corner radii use 3 tiers matching macOS HIG patterns.
enum DS {

    // MARK: - Primitive Tokens

    /// Typography scale — SwiftUI semantic styles with SF Pro (system default).
    /// Only `scoreLg` uses `.rounded` design for playful accent.
    enum Font {
        // System semantic styles (auto-adapt to macOS sizing)
        /// 10pt Regular — system caption
        static let caption   = SwiftUI.Font.caption
        /// 10pt Medium — system caption2
        static let caption2  = SwiftUI.Font.caption2
        /// 10pt Regular — footnotes, secondary info
        static let footnote  = SwiftUI.Font.footnote
        /// 11pt Regular — plain subheadline
        static let subhead   = SwiftUI.Font.subheadline
        /// 13pt Regular — body text (macOS default)
        static let body      = SwiftUI.Font.body
        /// 13pt Bold — emphasized body text
        static let headline  = SwiftUI.Font.headline
        /// 15pt Regular — section titles
        static let title     = SwiftUI.Font.title3
        /// 17pt Regular — dashboard header
        static let titleLg   = SwiftUI.Font.title2

        // Weighted variants (for emphasis)
        /// 11pt Medium — emphasized subheadline
        static let subheadMedium = SwiftUI.Font.subheadline.weight(.medium)
        /// 11pt Semibold — bold subheadline
        static let subheadBold   = SwiftUI.Font.subheadline.weight(.semibold)
        /// 15pt Semibold — bold section titles
        static let titleBold     = SwiftUI.Font.title3.weight(.semibold)
        /// 17pt Semibold — bold dashboard header
        static let titleLgBold   = SwiftUI.Font.title2.weight(.semibold)

        // Display/hero (rounded for playful accent)
        /// 32pt bold rounded — large score number
        static let scoreLg   = SwiftUI.Font.system(size: 32, weight: .bold, design: .rounded)
        /// 22pt — emoji display in score ring
        static let emoji     = SwiftUI.Font.system(size: 22)
        // Specialty
        /// 11pt monospaced — CVA debug overlay
        static let mono      = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced)
        /// 10pt — tiny badge icons (was 8pt, raised to legible minimum)
        static let badgeIcon = SwiftUI.Font.system(size: 10)
        /// 10pt — privacy footer, tiny labels (was 9pt, now proper 10pt via caption2)
        static let micro     = SwiftUI.Font.caption2
        /// 10pt — badge text, small indicators (now semantic caption)
        static let mini      = SwiftUI.Font.caption
        /// 12pt Regular — callout text (semantic)
        static let callout   = SwiftUI.Font.callout
    }

    /// Spacing scale — 8pt base grid, 4pt half-unit minimum.
    enum Space {
        /// 4pt — minimum spacing (badge gaps, tight elements)
        static let xs:  CGFloat = 4
        /// 8pt — standard gap (8pt grid base)
        static let sm:  CGFloat = 8
        /// 12pt — card padding compact
        static let md:  CGFloat = 12
        /// 16pt — content padding, section spacing
        static let lg:  CGFloat = 16
        /// 20pt — large section gaps
        static let xl:  CGFloat = 20
        /// 24pt — major breaks
        static let xxl: CGFloat = 24
    }

    /// Corner radius scale — 3 tiers matching macOS HIG.
    enum Radius {
        /// 4pt — accent bars, tiny decorative elements
        static let sm: CGFloat  = 4
        /// 8pt — buttons, small cards, badges
        static let md: CGFloat  = 8
        /// 12pt — main cards, overlays, containers
        static let lg: CGFloat  = 12
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
        static let title    = Font.titleBold
        static let body     = Font.subhead
        static let detail   = Font.footnote
        static let menuBar  = Font.caption
    }

    /// Onboarding typography — larger scale for welcome/setup windows.
    enum Onboarding {
        /// 22pt Semibold — step title (app name)
        static let title       = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// 14pt Regular — body / description text
        static let body        = SwiftUI.Font.system(size: 14)
        /// 16pt Medium — card titles, buttons
        static let bodyMedium  = SwiftUI.Font.system(size: 16, weight: .medium)
        /// 13pt Regular — secondary descriptions in cards
        static let detail      = SwiftUI.Font.system(size: 13)
    }

    /// Standard component dimensions.
    enum Size {
        static let scoreRing: CGFloat = 56
        static let scoreStroke: CGFloat = 6
        static let statusDot: CGFloat = 10
        static let crosshair: CGFloat = 36
        static let headWidget: CGFloat = 40
        static let colorAccentBar: CGFloat = 4
    }
}
