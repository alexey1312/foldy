import SwiftUI

// Liquid Glass, with the macOS 14 floor kept.
//
// Every glass API arrived in macOS 26 Tahoe and Foldy still runs on Sonoma, so the
// choice between glass and the control it replaces is made here, once, instead of an
// `if #available` at each call site. Before Tahoe the fallbacks are the controls Foldy
// used all along, so nothing looks half-finished.
//
// Glass belongs to the navigation layer only — buttons, pills, the bar that floats over
// the preview. Content (the settings cards, the style thumbnails, text) keeps its flat
// background: glass cannot sample glass, and a page of it reads as noise. Apple's advice
// is the same: limit the effect to the most important functional elements.

/// How much weight a button carries: the ordinary action, or the one its section is about.
enum GlassButtonProminence {
    case standard, prominent
}

extension View {
    /// `.glass` / `.glassProminent` on Tahoe, `.bordered` / `.borderedProminent` before it.
    ///
    /// No `.tint(.clear)` on the plain style, whatever the migration guides say. On macOS
    /// the tint reaches the label as well as the material, so a clear tint leaves the
    /// title invisible in the window that has focus — which is the only window anyone is
    /// looking at. Untinted, the label keeps its normal contrast.
    ///
    /// `.glassProminent` ignores a tint here and draws a high-contrast capsule instead:
    /// white on a light window, near-white on a dark one. That is the system's idea of
    /// prominent, so nothing passes a tint to it either.
    @ViewBuilder
    func glassButtonStyle(_ prominence: GlassButtonProminence = .standard, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            switch prominence {
            case .standard: buttonStyle(.glass).tint(tint)
            case .prominent: buttonStyle(.glassProminent).tint(tint)
            }
        } else {
            switch prominence {
            case .standard: buttonStyle(.bordered).tint(tint)
            case .prominent: buttonStyle(.borderedProminent).tint(tint)
            }
        }
    }

    /// Glass in `shape` on Tahoe; before it, the material that stood in for it, with a
    /// hairline rim. `.regularMaterial` rather than a flat colour, so the fallback
    /// follows the appearance the way glass does.
    @ViewBuilder
    func glassBackground(in shape: some InsettableShape, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(shape.fill(.regularMaterial))
                .overlay { shape.strokeBorder(.primary.opacity(0.08)) }
        }
    }

    /// Ties this view to `id` so its glass flows into its neighbours as it comes and
    /// goes, instead of fading. Only has an effect inside a ``GlassGroup``.
    @ViewBuilder
    func glassMorphID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// `GlassEffectContainer` on Tahoe, a plain passthrough before it.
///
/// Glass cannot sample other glass, so neighbouring pills each open their own backdrop
/// and end up looking subtly different — and every backdrop costs three offscreen
/// textures. One container gives them a shared sampling region and lets them morph into
/// one another.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
