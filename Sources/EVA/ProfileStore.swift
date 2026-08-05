import Foundation

struct ProfileStore {
    private let defaults: UserDefaults
    private let profileKey = "companionProfile.v1"
    private let completedKey = "hasCompletedOnboarding.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CompanionProfile? {
        guard defaults.bool(forKey: completedKey),
              let data = defaults.data(forKey: profileKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CompanionProfile.self, from: data)
    }

    func save(_ profile: CompanionProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
        defaults.set(true, forKey: completedKey)
    }
}
