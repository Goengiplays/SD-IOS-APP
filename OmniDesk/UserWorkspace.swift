import Foundation
import Clerk

struct WorkspaceProfile: Codable {
    var name = ""
    var email = ""
    var phone = ""
    var company = ""

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@") &&
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class UserWorkspace: ObservableObject {
    @Published private(set) var userID: String?
    @Published var profile = WorkspaceProfile()
    @Published private(set) var connectedStores: [String] = []
    @Published private(set) var hasDeveloperRole = false

    var isRealAccount: Bool { userID != nil }
    var hasStores: Bool { !connectedStores.isEmpty }
    var isDeveloper: Bool { hasDeveloperRole }

    func configure(with user: User?) {
        guard let user else {
            userID = nil
            profile = WorkspaceProfile()
            connectedStores = []
            hasDeveloperRole = false
            return
        }
        guard userID != user.id else { return }
        userID = user.id
        hasDeveloperRole = user.primaryEmailAddress?.emailAddress.lowercased() == "goengiplays@gmail.com"

        if let data = UserDefaults.standard.data(forKey: profileKey),
           let saved = try? JSONDecoder().decode(WorkspaceProfile.self, from: data) {
            profile = saved
        } else {
            profile = WorkspaceProfile(
                name: [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " "),
                email: user.primaryEmailAddress?.emailAddress ?? "",
                phone: user.primaryPhoneNumber?.phoneNumber ?? "",
                company: ""
            )
        }
        connectedStores = UserDefaults.standard.stringArray(forKey: storesKey) ?? []
    }

    func saveProfile(_ updatedProfile: WorkspaceProfile) {
        profile = updatedProfile
        guard let data = try? JSONEncoder().encode(updatedProfile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    func addStore(_ identifier: String) {
        guard isRealAccount else { return }
        if !connectedStores.contains(identifier) {
            connectedStores.append(identifier)
            UserDefaults.standard.set(connectedStores, forKey: storesKey)
        }
    }

    private var profileKey: String {
        "shipdemon.workspace.\(userID ?? "none").profile"
    }

    private var storesKey: String {
        "shipdemon.workspace.\(userID ?? "none").stores"
    }
}
