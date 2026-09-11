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
    /// `.glassProminent` ignores a tint on macOS, explicit or not, and draws a
    /// monochrome capsule: white on a light window, near-white on a dark one. In the
    /// light appearance that is the same colour as the plain `.glass` next to it, so the
    /// one action a screen is about looked no heavier than its neighbour. Prominent is
    /// therefore ``ProminentGlassButtonStyle``: clear glass over an accent capsule,
    /// the colour `.borderedProminent` has always carried.
    @ViewBuilder
    func glassButtonStyle(_ prominence: GlassButtonProminence = .standard) -> some View {
        if #available(macOS 26.0, *) {
            switch prominence {
            case .standard: buttonStyle(.glass)
            case .prominent: buttonStyle(ProminentGlassButtonStyle())
            }
        } else {
            switch prominence {
            case .standard: buttonStyle(.bordered)
            case .prominent: buttonStyle(.borderedProminent)
            }
        }
    }

    /// `.animation(_:value:)` for motion that only decorates: off under Reduce Motion.
    /// Motion that is feedback for a drag or a press is not decoration and stays.
    func decorativeAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(DecorativeAnimation(animation: animation, value: value))
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

private struct DecorativeAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// The accent-coloured primary button: a capsule of the accent with clear Liquid Glass
/// over it, so the colour is the backdrop the glass refracts. `Glass.tint` was tried
/// first, on `.regular` and on `.clear`, and came out as a faint wash on macOS, no
/// heavier than plain glass; `.regular` over the capsule whitened the accent to a pale
/// cyan in the light appearance. `.clear` leaves the colour alone and keeps the rim,
/// the highlight and `.interactive()`'s response to the pointer.
///
/// The insets follow what `.glass` draws for each `controlSize`, measured from the
/// window images, so a prominent button sits level with the plain ones beside it.
@available(macOS 26.0, *)
struct ProminentGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let m = metrics
        return configuration.label
            .font(.system(size: m.font, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, m.horizontal)
            .padding(.vertical, m.vertical)
            .contentShape(.capsule)
            .contentShape(.focusEffect, Capsule())
            .glassEffect(.clear.interactive(), in: .capsule)
            .background(Capsule().fill(Color.accentColor))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    /// Label size and the insets around it, per control size.
    private var metrics: (font: CGFloat, horizontal: CGFloat, vertical: CGFloat) {
        switch controlSize {
        case .mini: (9, 8, 2)
        case .small: (11, 9, 3)
        case .large, .extraLarge: (15, 16, 6.5)
        default: (13, 12, 5)
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
