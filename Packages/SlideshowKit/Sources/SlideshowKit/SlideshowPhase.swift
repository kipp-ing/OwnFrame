/// Beobachtbarer Zustand der Diashow. Der aktuelle Bildbezug (Asset-ID + Daten) liegt im ViewModel,
/// nicht im Enum-Case (schlanke Phase).
public enum SlideshowPhase: Sendable, Equatable {
    /// Assetliste wird geladen.
    case loading
    /// At least one displayable image is available; the slideshow is running.
    case playing
    /// The album contains no displayable images (FR-009).
    case empty
    /// Assetliste nicht abrufbar bzw. kein Bild ladbar (FR-010); erlaubt `retry()`.
    case failed
}
