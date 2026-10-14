import SwiftUI
import AppKit

/// Wraps a page's content in the standard scroll view, padding, content column,
/// and backdrop. Every page's `body` starts here so the chrome stays identical.
struct PageScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.section) {
                content
            }
            .padding(Layout.page)
            .frame(maxWidth: Layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppBackground())
    }
}

/// The title block at the top of every page.
///
/// Actions are buttons only. Text fields and pickers belong in a `SectionCard`
/// below the header, where they get room to breathe.
struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    var icon: String? = nil
    var isBusy: Bool = false
    var navigateBack: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let navigateBack {
                    Button {
                        navigateBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .help("Back to the overview")
                    .accessibilityLabel("Back to the overview")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                        Text(title)
                            .font(.largeTitle.weight(.semibold))
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // A single instantiation of `actions` — duplicating the builder
            // (as a ViewThatFits would) gives controls inside it two identities.
            HStack(spacing: Layout.control) {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassPanel()
    }
}

extension PageHeader where Actions == EmptyView {
    init(
        title: String,
        subtitle: String,
        icon: String? = nil,
        isBusy: Bool = false,
        navigateBack: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            isBusy: isBusy,
            navigateBack: navigateBack,
            actions: { EmptyView() }
        )
    }
}

/// A scrollable monospaced console with copy, save, and clear affordances.
/// Shared by every page that surfaces raw command output.
struct OutputConsole: View {
    let text: String
    var title: String = "Output"
    var isRunning: Bool = false
    var minHeight: CGFloat = 300
    var onClear: (() -> Void)? = nil

    var body: some View {
        SectionCard(title, icon: "terminal") {
            if isRunning {
                StatusBanner(message: "Running…", tone: .running)
            }

            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: minHeight)
            .background(
                AnyShapeStyle(.quaternary.opacity(0.25)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            HStack(spacing: Layout.control) {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)

                Button("Save…", systemImage: "square.and.arrow.down") {
                    saveToFile()
                }
                .disabled(text.isEmpty)

                if let onClear {
                    Button("Clear", systemImage: "xmark.circle") {
                        onClear()
                    }
                    .disabled(text.isEmpty)
                }

                Spacer()
            }
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title.replacingOccurrences(of: " ", with: "-"))-\(Int(Date.now.timeIntervalSince1970)).txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(text.utf8).write(to: url)
    }
}

/// A page that is just a header plus a console. Used by the read-only
/// `system_profiler`-style screens.
struct ToolShell<Actions: View>: View {
    let title: String
    let subtitle: String
    var icon: String? = nil
    var navigateBack: (() -> Void)? = nil
    let output: String
    var isRunning: Bool = false
    var onClear: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        PageScaffold {
            PageHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                isBusy: isRunning,
                navigateBack: navigateBack
            ) {
                actions
            }

            OutputConsole(text: output, isRunning: isRunning, onClear: onClear)
        }
    }
}

/// A labelled text field sized for a form grid.
struct FormField: View {
    let label: String
    @Binding var text: String
    var prompt: String? = nil
    var width: CGFloat? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: $text, prompt: prompt.map { Text($0) })
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmit?() }
        }
        .frame(width: width)
    }
}

/// An adaptive grid for form fields and action buttons.
struct FormGrid<Content: View>: View {
    var minimum: CGFloat = 180
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            content
        }
    }
}
