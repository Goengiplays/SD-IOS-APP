import Foundation
import Security
import SwiftUI
import Clerk

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var currentEmail: String

    private let service = "com.northstar.omnidesk.auth"
    private let sessionKey = "omnidesk.authenticated"

    init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: sessionKey)
        currentEmail = UserDefaults.standard.string(forKey: "omnidesk.email") ?? ""
    }

    func createAccount(name: String, email: String, password: String) -> String? {
        guard name.trimmingCharacters(in: .whitespaces).count >= 2 else { return "Enter your full name." }
        guard email.contains("@") else { return "Enter a valid email address." }
        guard password.count >= 8 else { return "Password must be at least 8 characters." }

        savePassword(password, account: email.lowercased())
        UserDefaults.standard.set(name, forKey: "omnidesk.name")
        completeSession(email: email)
        return nil
    }

    func signIn(email: String, password: String) -> String? {
        let normalized = email.lowercased()
        guard let saved = readPassword(account: normalized), saved == password else {
            return "The email or password is incorrect."
        }
        completeSession(email: normalized)
        return nil
    }

    func useDemoAccount() {
        let email = "demo@omnidesk.app"
        savePassword("omnidesk-demo", account: email)
        UserDefaults.standard.set("Rich G.", forKey: "omnidesk.name")
        completeSession(email: email)
    }

    func signOut() {
        UserDefaults.standard.set(false, forKey: sessionKey)
        isAuthenticated = false
    }

    private func completeSession(email: String) {
        currentEmail = email.lowercased()
        UserDefaults.standard.set(currentEmail, forKey: "omnidesk.email")
        UserDefaults.standard.set(true, forKey: sessionKey)
        withAnimation(.snappy) { isAuthenticated = true }
    }

    private func savePassword(_ password: String, account: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    private func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ShipDemonAuthView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var authIsPresented = false

    var body: some View {
        ZStack {
            Color(red: 0.992, green: 0.975, blue: 0.987).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color(red: 0.88, green: 0.08, blue: 0.24))
                        Text("Ship Demon")
                            .font(.system(size: 38, weight: .bold))
                        Text("Your stores, orders, money, and assistant in one place.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Label("Secure account access", systemImage: "lock.shield.fill")
                            .font(.headline)
                        Text("Sign in or create your Ship Demon account with Clerk. Email verification, password recovery, and multi-factor authentication are handled securely.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            authIsPresented = true
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.96, green: 0.04, blue: 0.18), Color(red: 0.63, green: 0.08, blue: 0.70)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                        }

                        Button("Explore with demo account") {
                            auth.useDemoAccount()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .purple.opacity(0.12), radius: 28, y: 14)

                    Text("Your password and verification details are managed by Clerk, not stored by Ship Demon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .padding(.top, 30)
            }
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
    }
}
