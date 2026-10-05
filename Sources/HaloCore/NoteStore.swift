import Foundation
import Combine

/// A local scratchpad. Each edit reaches preferences immediately; there is no
/// debounce task to lose the last edit when the island closes or Halo quits.
public final class NoteStore: ObservableObject {
    private let defaults: UserDefaults
    private let key = "quickNote"
    @Published public var text: String {
        didSet {
            guard text != oldValue else { return }
            defaults.set(text, forKey: key)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: key) ?? ""
    }
}
