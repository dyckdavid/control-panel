import SwiftUI

/// Shared spacing and corner metrics so every page lines up on the same grid.
enum Layout {
    /// Outer padding around a page's content.
    static let page: CGFloat = 24
    /// Vertical gap between the major blocks of a page.
    static let section: CGFloat = 18
    /// Inner padding of a card.
    static let card: CGFloat = 18
    /// Gap between adjacent controls in a row.
    static let control: CGFloat = 10
    /// Corner radius of a card surface.
    static let corner: CGFloat = 16
    /// Widest the content column grows to before it stops stretching.
    static let contentWidth: CGFloat = 1180
}

// MARK: - Background

/// The window-filling backdrop shared by every page.
struct AppBackground: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
    }
}

// MARK: - Surfaces

/// The one card surface used across the app.
///
/// Cards use a material rather than Liquid Glass: a page can show a dozen of
/// them at once, and Apple's guidance is to keep the number of simultaneous
/// glass effects small. Glass is reserved for headers and prominent controls.
struct PanelSurface: ViewModifier {
    var corner: CGFloat = Layout.corner
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(borderStyle, lineWidth: isSelected ? 2 : 1)
            }
    }

    private var borderStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(.separator.opacity(0.35))
    }
}

extension View {
    func panelSurface(corner: CGFloat = Layout.corner, isSelected: Bool = false) -> some View {
        modifier(PanelSurface(corner: corner, isSelected: isSelected))
    }

    /// Applies Liquid Glass with the app's standard card shape.
    func glassPanel(corner: CGFloat = Layout.corner) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: corner))
    }
}

// MARK: - Tone

/// Semantic colouring shared by banners, badges, and stat cards.
enum Tone {
    case neutral
    case accent
    case success
    case warning
    case error
    case running

    var symbol: String {
        switch self {
        case .neutral: "info.circle"
        case .accent: "sparkles"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .running: "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .accent: .accentColor
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .running: .accentColor
        }
    }

    var fill: AnyShapeStyle {
        switch self {
        case .neutral: AnyShapeStyle(.quaternary.opacity(0.35))
        default: AnyShapeStyle(color.opacity(0.12))
        }
    }
}

// MARK: - Cards

/// A titled card that groups related content.
struct SectionCard<Content: View>: View {
    private let title: String
    private let icon: String?
    private let content: Content

    init(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.card)
        .panelSurface()
    }
}

/// A single headline metric.
struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    var icon: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(16)
        .panelSurface()
    }
}

/// An adaptive row of `StatCard`s that wraps instead of squashing.
struct StatRow<Content: View>: View {
    var minimum: CGFloat = 190
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum), spacing: 14)],
            alignment: .leading,
            spacing: 14
        ) {
            content
        }
    }
}

// MARK: - Rows

/// A label on the left, a selectable value on the right.
struct KeyValueRow: View {
    let title: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Placeholder text for an empty card.
struct EmptyStateRow: View {
    let message: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.tertiary)
            }
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// A small capsule label, e.g. "Default".
struct Badge: View {
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.fill, in: Capsule())
    }
}

/// An inline status message.
struct StatusBanner: View {
    let message: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if tone == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: tone.symbol)
                    .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Infers a tone from a free-form status string produced by a shell command.
func inferredTone(for message: String) -> Tone {
    if message.isEmpty { return .neutral }
    let lowered = message.lowercased()
    if ["failed", "error", "unable", "denied", "not found", "unavailable"].contains(where: lowered.contains) {
        return .warning
    }
    return .success
}
