import SwiftUI

/// The landing screen, shown until a tool is picked from the sidebar.
struct AppOverviewView: View {
    let openDestination: (SidebarDestination) -> Void

    @State private var expandedCategory: SidebarCategory?

    private static let quickActions: [SidebarDestination] = [
        .generalAbout, .networkDashboard, .printers, .privacySecurity
    ]

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Control Panel",
                subtitle: "A native utility hub for this Mac, with the tools you reach for most a click away.",
                icon: "square.grid.2x2"
            ) {
                Label("Pick a tool from the sidebar, or start below", systemImage: "sidebar.left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            SectionCard("Start Here", icon: "bolt") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(Self.quickActions) { destination in
                        quickActionCard(destination)
                    }
                }
            }

            SectionCard("Browse by Area", icon: "folder") {
                ForEach(SidebarCategory.allCases) { category in
                    categoryRow(category)
                    if category.id != SidebarCategory.allCases.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func quickActionCard(_ destination: SidebarDestination) -> some View {
        Button {
            openDestination(destination)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: destination.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)

                Text(destination.title)
                    .font(.headline)

                Text(destination.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .panelSurface(corner: 12)
        }
        .buttonStyle(.plain)
    }

    /// Tapping a category expands it in place, so every tool is reachable from
    /// the overview without a second screen.
    private func categoryRow(_ category: SidebarCategory) -> some View {
        let isExpanded = expandedCategory == category

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    expandedCategory = isExpanded ? nil : category
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .foregroundStyle(.tint)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(.headline)
                        Text(category.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Badge(text: "\(category.destinations.count)")

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(category.destinations) { destination in
                        Button {
                            openDestination(destination)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: destination.icon)
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                    .frame(width: 16)
                                Text(destination.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if destination.isMutating {
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .help("This tool can change system settings")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panelSurface(corner: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 4)
    }
}
