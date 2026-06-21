import SwiftUI
import Clerk

struct IntegrationCredential: Identifiable, Hashable {
    let id: String
    let title: String
    let provider: String
    let icon: String
    let tint: Color
    let isSecret: Bool

    static let catalog: [IntegrationCredential] = [
        .init(id: "SHOPIFY_API_KEY", title: "API key", provider: "Shopify", icon: "bag.fill", tint: .green, isSecret: false),
        .init(id: "SHOPIFY_API_SECRET", title: "API secret", provider: "Shopify", icon: "key.fill", tint: .green, isSecret: true),
        .init(id: "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY", title: "Publishable key", provider: "Clerk", icon: "person.badge.shield.checkmark.fill", tint: .purple, isSecret: false),
        .init(id: "CLERK_SECRET_KEY", title: "Secret key", provider: "Clerk", icon: "key.fill", tint: .purple, isSecret: true),
        .init(id: "OPENAI_API_KEY", title: "API key", provider: "OpenAI", icon: "sparkles", tint: .black, isSecret: true),
        .init(id: "EASYPOST_API_KEY_TEST", title: "Test API key", provider: "EasyPost", icon: "shippingbox.fill", tint: .blue, isSecret: true),
        .init(id: "EASYPOST_API_KEY_PRODUCTION", title: "Production API key", provider: "EasyPost", icon: "shippingbox.fill", tint: .blue, isSecret: true),
        .init(id: "USPS_ACCOUNT_NUMBER", title: "Account number", provider: "USPS", icon: "envelope.fill", tint: .indigo, isSecret: true),
        .init(id: "USPS_CRID", title: "CRID", provider: "USPS", icon: "number", tint: .indigo, isSecret: true),
        .init(id: "DATABASE_URL", title: "Database URL", provider: "Infrastructure", icon: "cylinder.split.1x2.fill", tint: .orange, isSecret: true),
        .init(id: "ENCRYPTION_KEY", title: "Encryption key", provider: "Infrastructure", icon: "lock.fill", tint: .orange, isSecret: true)
    ]
}

struct IntegrationCredentialStatus: Decodable {
    let key: String
    let configured: Bool
    let updatedAt: Date?
}

private struct IntegrationStatusEnvelope: Decodable {
    let credentials: [IntegrationCredentialStatus]
}

enum IntegrationAdminError: LocalizedError {
    case backendNotConfigured
    case unauthorized
    case endpointUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "The Ship Demon backend URL is not configured."
        case .unauthorized:
            return "Your account is not authorized to manage integration keys."
        case .endpointUnavailable:
            return "The secure configuration endpoint has not been deployed yet."
        case .invalidResponse:
            return "The server returned an invalid response."
        }
    }
}

actor IntegrationAdminService {
    static let shared = IntegrationAdminService()

    private var baseURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "SHIP_DEMON_API_BASE_URL") as? String,
              !rawValue.isEmpty else { return nil }
        return URL(string: rawValue)
    }

    func statuses(authorizationToken: String) async throws -> [IntegrationCredentialStatus] {
        guard let baseURL else { throw IntegrationAdminError.backendNotConfigured }
        var request = URLRequest(url: baseURL.appending(path: "api/mobile/admin/integrations"))
        request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IntegrationStatusEnvelope.self, from: data).credentials
    }

    func rotate(key: String, value: String, authorizationToken: String) async throws {
        guard let baseURL else { throw IntegrationAdminError.backendNotConfigured }
        var request = URLRequest(url: baseURL.appending(path: "api/mobile/admin/integrations"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["key": key, "value": value])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw IntegrationAdminError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw IntegrationAdminError.unauthorized
        case 404: throw IntegrationAdminError.endpointUnavailable
        default: throw IntegrationAdminError.invalidResponse
        }
    }
}

struct IntegrationAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statuses: [String: IntegrationCredentialStatus] = [:]
    @State private var selectedCredential: IntegrationCredential?
    @State private var isLoading = true
    @State private var message: String?

    private var providers: [String] {
        Array(Set(IntegrationCredential.catalog.map(\.provider))).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    vaultHero
                    if let message {
                        Label(message, systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }

                    ForEach(providers, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(provider.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(IntegrationCredential.catalog.filter { $0.provider == provider }) { credential in
                                    credentialRow(credential)
                                    if credential.id != IntegrationCredential.catalog.filter({ $0.provider == provider }).last?.id {
                                        Divider().padding(.leading, 54)
                                    }
                                }
                            }
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.045), radius: 18, y: 8)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(Color(red: 0.965, green: 0.98, blue: 0.97))
            .navigationTitle("Integration Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadStatuses() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await loadStatuses() }
            .sheet(item: $selectedCredential) { credential in
                CredentialRotationView(credential: credential) {
                    Task { await loadStatuses() }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var vaultHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(red: 0.94, green: 0.08, blue: 0.24))
                Spacer()
                Text("OWNER")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            Text("Protected configuration")
                .font(.title2.weight(.semibold))
            Text("Replace credentials without revealing the current value. Secret keys are sent only to the authenticated backend and are never stored on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Color(red: 0.06, green: 0.09, blue: 0.075), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .purple.opacity(0.16), radius: 24, y: 12)
    }

    private func credentialRow(_ credential: IntegrationCredential) -> some View {
        Button {
            selectedCredential = credential
        } label: {
            HStack(spacing: 13) {
                Image(systemName: credential.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(credential.tint)
                    .frame(width: 36, height: 36)
                    .background(credential.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(credential.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(credential.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(statuses[credential.id]?.configured == true ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 8, height: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadStatuses() async {
        isLoading = true
        do {
            guard let token = try await Clerk.shared.session?.getToken()?.jwt else {
                throw IntegrationAdminError.unauthorized
            }
            let result = try await IntegrationAdminService.shared.statuses(authorizationToken: token)
            statuses = Dictionary(uniqueKeysWithValues: result.map { ($0.key, $0) })
            message = nil
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }
}

private struct CredentialRotationView: View {
    @Environment(\.dismiss) private var dismiss
    let credential: IntegrationCredential
    let didSave: () -> Void
    @State private var value = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("Replace \(credential.title)", systemImage: credential.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(credential.tint)
                Text("The current value stays hidden. Saving creates an audited rotation request on the Ship Demon backend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Group {
                    if credential.isSecret {
                        SecureField("Enter new value", text: $value)
                    } else {
                        TextField("Enter new value", text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .font(.body.monospaced())
                .padding(15)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save replacement")
                        }
                    }
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
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                Spacer()
            }
            .padding(20)
            .navigationTitle(credential.provider)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            guard let token = try await Clerk.shared.session?.getToken()?.jwt else {
                throw IntegrationAdminError.unauthorized
            }
            try await IntegrationAdminService.shared.rotate(
                key: credential.id,
                value: value,
                authorizationToken: token
            )
            value = ""
            didSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
