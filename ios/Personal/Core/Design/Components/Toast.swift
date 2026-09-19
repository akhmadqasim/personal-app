import Foundation
import SwiftUI

/// What a toast says and how it looks (§3 "Toast"). `nonisolated` and
/// `Sendable` so a background task can build one and hand it to the UI.
nonisolated struct ToastItem: Equatable, Identifiable, Sendable {

    enum Kind: Equatable, Sendable {
        /// `success` fill, check symbol — "Session saved".
        case success
        /// `danger` fill, warning symbol — the failure sentence of `ApiError`.
        case error
    }

    var id: UUID
    var kind: Kind
    var message: String

    init(id: UUID = UUID(), kind: Kind, message: String) {
        self.id = id
        self.kind = kind
        self.message = message
    }

    static func success(_ message: String) -> ToastItem {
        ToastItem(kind: .success, message: message)
    }

    static func error(_ message: String) -> ToastItem {
        ToastItem(kind: .error, message: message)
    }
}

/// The capsule itself: 44 pt, full-colour fill, white symbol and label.
struct ToastView: View {

    var item: ToastItem

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
            Text(item.message)
                .font(Theme.Typography.headline)
                .lineLimit(2)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: 44)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.kind {
        case .success: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var fill: Color {
        switch item.kind {
        case .success: Theme.Colors.success
        case .error: Theme.Colors.danger
        }
    }
}

/// Shows `item` as a toast at the top of the screen and clears it after
/// 2.5 s. The slide is 250 ms (§5 "Motion").
struct ToastModifier: ViewModifier {

    @Binding var item: ToastItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let item {
                    ToastView(item: item)
                        .padding(.horizontal, Theme.Spacing.screenInset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: item)
            // `task(id:)` restarts the countdown whenever a new toast replaces
            // the current one, and cancels it when the toast is dismissed.
            .task(id: item) {
                guard item != nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                guard Task.isCancelled == false else { return }
                item = nil
            }
    }
}

extension View {
    /// `.toast($toast)` on a screen's root view.
    func toast(_ item: Binding<ToastItem?>) -> some View {
        modifier(ToastModifier(item: item))
    }
}

// MARK: - Previews

private struct ToastGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ToastView(item: .success("Session saved"))
            ToastView(item: .error("No connection. Changes are saved on this device"))
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    ToastGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ToastGallery()
        .preferredColorScheme(.dark)
}
