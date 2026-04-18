/// Animation style for the attachment picker's tab content transitions.
///
/// The library defaults to ``slide`` — a horizontal slide whose direction matches the
/// tab order (tabs to the right of the selected one enter from the right; tabs to the
/// left enter from the left). Host apps may override this via
/// ``FCLAttachmentDelegate/tabTransition`` to use an opacity ``crossfade`` instead.
public enum FCLPickerTabTransition: Sendable, Hashable {
    /// Horizontal slide; direction matches tab order. Default.
    case slide
    /// Opacity crossfade; no spatial direction.
    case crossfade
}
