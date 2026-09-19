import SwiftUI

/// The event row of the design system (§3 "List row"): a 72 pt square
/// thumbnail with an optional status pill overlapping its bottom-left corner,
/// then a caption, a two-line title and one or two symbol-led meta lines, with
/// an optional trailing accessory.
///
/// Rows are separated by `Theme.Spacing.rowSpacing`, not by hairlines — that
/// is the list's job, not the row's.
struct ThumbnailRow<Thumbnail: View, Trailing: View>: View {

    /// One meta line: a 16 pt SF Symbol and its text.
    typealias Meta = (symbol: String, text: String)

    var thumbnail: Thumbnail
    var caption: String?
    var title: String
    var meta: [Meta]
    var pill: StatusPill?
    var trailing: Trailing

    /// Thumbnails grow with Dynamic Type and cap at 88 pt (spec §6).
    @ScaledMetric(relativeTo: .headline) private var scaledThumbnail: CGFloat = 72

    init(
        @ViewBuilder thumbnail: () -> Thumbnail,
        caption: String? = nil,
        title: String,
        meta: [Meta] = [],
        pill: StatusPill? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.thumbnail = thumbnail()
        self.caption = caption
        self.title = title
        self.meta = meta
        self.pill = pill
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            thumbnailView
            textColumn
            Spacer(minLength: Theme.Spacing.sm)
            trailing
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
        .contentShape(Rectangle())
    }

    private var thumbnailSize: CGFloat {
        min(scaledThumbnail, 88)
    }

    private var thumbnailView: some View {
        thumbnail
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let pill {
                    pill
                        .offset(x: -Theme.Spacing.sm, y: Theme.Spacing.sm)
                }
            }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let caption {
                Text(caption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            ForEach(meta.indices, id: \.self) { index in
                metaLine(meta[index])
            }
        }
    }

    private func metaLine(_ item: Meta) -> some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 16)
            Text(item.text)
                .font(Theme.Typography.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
    }
}

// MARK: - Without a trailing accessory

extension ThumbnailRow where Trailing == EmptyView {
    init(
        @ViewBuilder thumbnail: () -> Thumbnail,
        caption: String? = nil,
        title: String,
        meta: [Meta] = [],
        pill: StatusPill? = nil
    ) {
        self.init(
            thumbnail: thumbnail,
            caption: caption,
            title: title,
            meta: meta,
            pill: pill,
            trailing: { EmptyView() })
    }
}

// MARK: - Previews

private struct ThumbnailRowGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.rowSpacing) {
            ThumbnailRow(
                thumbnail: { tile("chest", symbol: "dumbbell") },
                caption: "Push A · Week 3",
                title: "Barbell Bench Press",
                meta: [("dumbbell", "Barbell · Chest"), ("clock", "48 min")],
                pill: StatusPill(.completed),
                trailing: {
                    Text("+2.5 kg")
                        .font(Theme.Typography.pill)
                        .foregroundStyle(Theme.Colors.success)
                })
            ThumbnailRow(
                thumbnail: { tile("back", symbol: "figure.strengthtraining.traditional") },
                caption: "Yesterday",
                title: "Pull B",
                meta: [("flame", "7 exercises")],
                pill: StatusPill(.skipped))
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }

    private func tile(_ muscleGroup: String, symbol: String) -> some View {
        Theme.soft(for: muscleGroup)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.accent(for: muscleGroup))
            }
    }
}

#Preview("Light") {
    ThumbnailRowGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ThumbnailRowGallery()
        .preferredColorScheme(.dark)
}
