import Foundation

struct AffectiveStateStore {
    private let defaults: UserDefaults
    private let key = "affectiveState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AffectiveState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AffectiveState.self, from: data)
    }

    func save(_ state: AffectiveState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
