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
    /// therefore ``ProminentGlassButtonStyle``: the same glass, tinted with the accent,
    /// the way `.borderedProminent` has always been.
    @ViewBuilder
    func glassButtonStyle(_ prominence: GlassButtonProminence = .standard, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            switch prominence {
            case .standard: buttonStyle(.glass).tint(tint)
            case .prominent: buttonStyle(ProminentGlassButtonStyle(tint: tint ?? .accentColor))
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

/// The accent-coloured primary button: a capsule of `tint` with clear Liquid Glass
/// over it, so the colour is the backdrop the glass refracts. `Glass.tint` alone was
/// tried first and came out as a faint wash on macOS, no heavier than plain glass;
/// `.regular` over the capsule whitened the accent to a pale cyan in the light
/// appearance. `.clear` leaves the colour alone and keeps the rim, the highlight and
/// `.interactive()`'s response to the pointer. Sized to sit beside `.glass` buttons
/// of the same `controlSize`.
@available(macOS 26.0, *)
struct ProminentGlassButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .contentShape(.capsule)
            .glassEffect(.clear.interactive(), in: .capsule)
            .background(Capsule().fill(tint))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: 18
        case .small: 20
        case .large, .extraLarge: 32
        default: 24
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini, .small: 9
        case .large, .extraLarge: 16
        default: 12
        }
    }

    private var fontSize: CGFloat {
        switch controlSize {
        case .mini: 9
        case .small: 11
        case .large, .extraLarge: 15
        default: 13
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
