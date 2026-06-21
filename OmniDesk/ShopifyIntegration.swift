import Foundation

enum ShopifyIntegrationError: LocalizedError {
    case backendNotConfigured
    case invalidShop
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "Add SHIP_DEMON_API_BASE_URL to the app configuration."
        case .invalidShop:
            return "Enter a valid .myshopify.com store domain."
        case .invalidResponse:
            return "The Shopify connection service returned an invalid response."
        }
    }
}

struct ShopifyConnectionStatus: Decodable {
    let connected: Bool
    let shop: String
    let scopes: [String]
}

actor ShopifyIntegration {
    static let shared = ShopifyIntegration()

    private var baseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "SHIP_DEMON_API_BASE_URL") as? String,
            !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    func installationURL(for rawShop: String) throws -> URL {
        guard let baseURL else { throw ShopifyIntegrationError.backendNotConfigured }
        let shop = normalize(rawShop)
        guard shop.hasSuffix(".myshopify.com"), shop.count > ".myshopify.com".count else {
            throw ShopifyIntegrationError.invalidShop
        }

        var components = URLComponents(
            url: baseURL.appending(path: "v1/integrations/shopify/install"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "shop", value: shop),
            URLQueryItem(name: "return_to", value: "shipdemon://shopify/callback")
        ]
        guard let url = components?.url else { throw ShopifyIntegrationError.invalidResponse }
        return url
    }

    func connectionStatus() async throws -> ShopifyConnectionStatus {
        guard let baseURL else { throw ShopifyIntegrationError.backendNotConfigured }
        let url = baseURL.appending(path: "v1/integrations/shopify/status")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ShopifyIntegrationError.invalidResponse
        }
        return try JSONDecoder().decode(ShopifyConnectionStatus.self, from: data)
    }

    private func normalize(_ rawShop: String) -> String {
        rawShop.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
