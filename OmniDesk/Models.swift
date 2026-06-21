import Foundation
import SwiftUI

enum SalesChannel: String, CaseIterable, Identifiable {
    case all = "All"
    case shopify = "Shopify"
    case tiktok = "TikTok Shop"
    case amazon = "Amazon"
    case walmart = "Walmart"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .all: return "All"
        case .shopify: return "Shopify"
        case .tiktok: return "TikTok"
        case .amazon: return "Amazon"
        case .walmart: return "Walmart"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .shopify: return "bag.fill"
        case .tiktok: return "music.note"
        case .amazon: return "shippingbox.fill"
        case .walmart: return "sparkles"
        }
    }

    var logoAsset: String? {
        switch self {
        case .all: return nil
        case .shopify: return "ShopifyLogo"
        case .tiktok: return "TikTokLogo"
        case .amazon: return "AmazonLogo"
        case .walmart: return "WalmartLogo"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .primary
        case .shopify: return Color(red: 0.0, green: 0.48, blue: 0.36)
        case .tiktok: return Color(red: 0.08, green: 0.10, blue: 0.15)
        case .amazon: return Color(red: 0.94, green: 0.55, blue: 0.0)
        case .walmart: return Color(red: 0.0, green: 0.44, blue: 0.82)
        }
    }
}

enum OrderState: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case processing = "Processing"
    case message = "Needs reply"
    case hold = "On hold"
    case shipped = "Shipped"
    case delivered = "Delivered"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .ready: return Color(red: 0.0, green: 0.48, blue: 0.36)
        case .processing: return .blue
        case .message: return .pink
        case .hold: return .orange
        case .shipped: return .indigo
        case .delivered: return .green
        }
    }
}

struct MarketplaceConnection: Identifiable {
    let id = UUID()
    let name: String
    let channel: SalesChannel
    let subtitle: String
    let status: String
    let isConnected: Bool
}

struct Metric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let accent: Color
}

struct Order: Identifiable {
    let id: String
    let date: String
    let customer: String
    let email: String
    let phone: String
    let channel: SalesChannel
    let state: OrderState
    let total: String
    let items: String
    let itemCount: Int
    let carrier: String
    let tracking: String
    let address: String
    let note: String
    let paid: Bool

    var productImage: String {
        let name = items.lowercased()
        if name.contains("hydration") { return "HydrationKit" }
        if name.contains("skin reset") { return "SkinReset" }
        if name.contains("linen") { return "LinenOvershirt" }
        if name.contains("canvas tote") { return "CanvasTote" }
        if name.contains("ceramic") { return "CeramicDinner" }
        if name.contains("travel") { return "TravelOrganizer" }
        if name.contains("cap") { return "EverydayCap" }
        return "WellnessEssentials"
    }
}

struct Conversation: Identifiable {
    let id: String
    let customer: String
    let channel: SalesChannel
    let orderID: String
    let preview: String
    let time: String
    let unread: Int
    let priority: Bool
    var messages: [ChatMessage]
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let time: String
    let fromCustomer: Bool
}

struct Payout: Identifiable {
    let id = UUID()
    let channel: SalesChannel
    let amount: String
    let date: String
    let status: String
}

struct ExpenseItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
}

enum DemoData {
    static let connections = [
        MarketplaceConnection(name: "Northstar Goods", channel: .shopify, subtitle: "Primary storefront", status: "Live", isConnected: true),
        MarketplaceConnection(name: "Northstar TikTok", channel: .tiktok, subtitle: "US Seller Center", status: "Live", isConnected: true),
        MarketplaceConnection(name: "Northstar Amazon", channel: .amazon, subtitle: "Token expires in 3 days", status: "Renew", isConnected: true),
        MarketplaceConnection(name: "Walmart Marketplace", channel: .walmart, subtitle: "Not connected", status: "Connect", isConnected: false)
    ]

    static let metrics = [
        Metric(title: "Gross revenue", value: "$128,940", detail: "+18.4% this month", systemImage: "chart.line.uptrend.xyaxis", accent: .blue),
        Metric(title: "Open orders", value: "342", detail: "86 need labels", systemImage: "shippingbox.fill", accent: .green),
        Metric(title: "Net profit", value: "$41,820", detail: "32.4% margin", systemImage: "dollarsign.circle.fill", accent: .indigo),
        Metric(title: "Messages", value: "27", detail: "9 need a reply", systemImage: "bubble.left.and.bubble.right.fill", accent: .pink)
    ]

    private static let featuredOrders = [
        Order(id: "#OD-10492", date: "Today, 10:42 AM", customer: "Maya Chen", email: "maya@example.com", phone: "(718) 555-0142", channel: .shopify, state: .ready, total: "$184.20", items: "Linen Overshirt, Canvas Tote", itemCount: 2, carrier: "UPS Ground", tracking: "1Z93Y81A0392857712", address: "88 Kent Ave, Brooklyn, NY 11249", note: "Gift note requested", paid: true),
        Order(id: "#TT-88210", date: "Today, 9:18 AM", customer: "Jordan Miles", email: "jordan@example.com", phone: "(206) 555-0188", channel: .tiktok, state: .message, total: "$72.00", items: "Hydration Starter Kit", itemCount: 1, carrier: "USPS Priority", tracking: "Label not purchased", address: "450 Pine St, Seattle, WA 98101", note: "Asked if delivery can arrive before Friday", paid: true),
        Order(id: "#AMZ-71854", date: "Yesterday, 6:04 PM", customer: "Priya Shah", email: "priya@example.com", phone: "(512) 555-0109", channel: .amazon, state: .hold, total: "$246.90", items: "Ceramic Dinner Set", itemCount: 1, carrier: "DHL Express", tracking: "Address validation required", address: "Unit missing, Austin, TX 78704", note: "Carrier needs apartment number", paid: true),
        Order(id: "#OD-10488", date: "Yesterday, 3:31 PM", customer: "Theo Walker", email: "theo@example.com", phone: "(303) 555-0194", channel: .shopify, state: .shipped, total: "$91.45", items: "Everyday Cap, Socks 3-pack", itemCount: 2, carrier: "USPS Ground Advantage", tracking: "9400111899563427181197", address: "19 Elm St, Denver, CO 80203", note: "Repeat customer", paid: true),
        Order(id: "#TT-88196", date: "Yesterday, 1:12 PM", customer: "Amara King", email: "amara@example.com", phone: "(415) 555-0165", channel: .tiktok, state: .processing, total: "$139.00", items: "Skin Reset Bundle", itemCount: 1, carrier: "UPS 2nd Day Air", tracking: "Preparing shipment", address: "214 Mission St, San Francisco, CA 94105", note: "Influencer affiliate order", paid: true),
        Order(id: "#AMZ-71821", date: "Jun 11, 11:08 AM", customer: "Eli Brooks", email: "eli@example.com", phone: "(305) 555-0117", channel: .amazon, state: .delivered, total: "$58.80", items: "Travel Organizer", itemCount: 1, carrier: "Amazon Shipping", tracking: "TBA314709625000", address: "701 Ocean Dr, Miami, FL 33139", note: "Delivered at front desk", paid: true)
    ]

    static let orders: [Order] = {
        let names = ["Olivia Martin", "Noah Williams", "Ava Thompson", "Liam Davis", "Sophia Taylor", "Mason Wilson", "Isabella Moore", "Lucas Anderson", "Mia Jackson", "Ethan White"]
        let products = [
            ("Hydration Starter Kit", 72.00),
            ("Skin Reset Bundle", 139.00),
            ("Linen Overshirt", 118.00),
            ("Canvas Tote", 42.00),
            ("Ceramic Dinner Set", 246.90),
            ("Travel Organizer", 58.80),
            ("Everyday Cap", 38.00),
            ("Wellness Essentials", 96.50)
        ]
        let states: [OrderState] = [.ready, .processing, .shipped, .delivered, .message, .hold]
        var generated: [Order] = []

        for index in 0..<20 {
            let product = products[index % products.count]
            let customer = names[index % names.count]
            generated.append(
                Order(
                    id: "#AMZ-\(72000 + index)",
                    date: index < 6 ? "Today, \(9 + index):\(index.isMultiple(of: 2) ? "12" : "47") AM" : index < 12 ? "Yesterday, \(index):20 PM" : "Jun \(10 - index % 5), 2:15 PM",
                    customer: customer,
                    email: customer.lowercased().replacingOccurrences(of: " ", with: ".") + "@example.com",
                    phone: "(212) 555-\(String(format: "%04d", 1200 + index))",
                    channel: .amazon,
                    state: states[index % states.count],
                    total: String(format: "$%.2f", product.1 + Double(index % 4) * 12.50),
                    items: product.0,
                    itemCount: 1 + index % 3,
                    carrier: index.isMultiple(of: 2) ? "Amazon Shipping" : "UPS Ground",
                    tracking: index % 4 == 0 ? "Label not purchased" : "TBA\(314709625100 + index)",
                    address: "\(120 + index) Market St, New York, NY 100\(String(format: "%02d", index))",
                    note: index % 5 == 0 ? "Priority customer" : "Standard fulfillment",
                    paid: true
                )
            )
        }

        for index in 0..<30 {
            let product = products[(index + 2) % products.count]
            let customer = names[(index + 3) % names.count]
            generated.append(
                Order(
                    id: "#TT-\(89000 + index)",
                    date: index < 9 ? "Today, \(8 + index % 4):\(String(format: "%02d", 10 + index)) AM" : index < 18 ? "Yesterday, \(1 + index % 8):30 PM" : "Jun \(11 - index % 6), 4:05 PM",
                    customer: customer,
                    email: customer.lowercased().replacingOccurrences(of: " ", with: ".") + "@example.com",
                    phone: "(646) 555-\(String(format: "%04d", 2200 + index))",
                    channel: .tiktok,
                    state: states[(index + 1) % states.count],
                    total: String(format: "$%.2f", product.1 + Double(index % 5) * 9.25),
                    items: product.0,
                    itemCount: 1 + index % 2,
                    carrier: index.isMultiple(of: 3) ? "USPS Priority" : "UPS Ground",
                    tracking: index % 5 == 0 ? "Preparing shipment" : "940011189956342\(7182000 + index)",
                    address: "\(310 + index) Sunset Blvd, Los Angeles, CA 900\(String(format: "%02d", index))",
                    note: index % 4 == 0 ? "TikTok affiliate order" : "Standard fulfillment",
                    paid: true
                )
            )
        }

        return featuredOrders + generated
    }()

    static let conversations = [
        Conversation(id: "chat-1", customer: "Jordan Miles", channel: .tiktok, orderID: "#TT-88210", preview: "Can this arrive before Friday?", time: "2m", unread: 2, priority: true, messages: [
            ChatMessage(text: "Hi! I just placed this order. Can it arrive before Friday?", time: "10:41 AM", fromCustomer: true),
            ChatMessage(text: "Let me check the fastest available service for your address.", time: "10:43 AM", fromCustomer: false),
            ChatMessage(text: "Thank you! It is for a birthday.", time: "10:44 AM", fromCustomer: true)
        ]),
        Conversation(id: "chat-2", customer: "Priya Shah", channel: .amazon, orderID: "#AMZ-71854", preview: "My apartment is 4B.", time: "18m", unread: 1, priority: true, messages: [
            ChatMessage(text: "Hello, the apartment number is 4B. Sorry I missed it.", time: "10:18 AM", fromCustomer: true)
        ]),
        Conversation(id: "chat-3", customer: "Maya Chen", channel: .shopify, orderID: "#OD-10492", preview: "Thanks for adding the gift note!", time: "1h", unread: 0, priority: false, messages: [
            ChatMessage(text: "Could you include the gift note from my checkout?", time: "9:14 AM", fromCustomer: true),
            ChatMessage(text: "Absolutely. It has been added to your packing slip.", time: "9:20 AM", fromCustomer: false),
            ChatMessage(text: "Thanks for adding the gift note!", time: "9:21 AM", fromCustomer: true)
        ]),
        Conversation(id: "chat-4", customer: "Theo Walker", channel: .shopify, orderID: "#OD-10488", preview: "Where can I track my package?", time: "3h", unread: 1, priority: false, messages: [
            ChatMessage(text: "Where can I track my package?", time: "7:36 AM", fromCustomer: true)
        ])
    ]

    static let payouts = [
        Payout(channel: .shopify, amount: "$18,420.18", date: "Arrives Jun 14", status: "In transit"),
        Payout(channel: .tiktok, amount: "$9,718.40", date: "Estimated Jun 16", status: "Processing"),
        Payout(channel: .amazon, amount: "$14,206.72", date: "Settlement Jun 18", status: "Pending")
    ]

    static let expenses = [
        ExpenseItem(title: "Product costs", value: "$38,410", detail: "29.8% of revenue", systemImage: "cube.box.fill", tint: .indigo),
        ExpenseItem(title: "Ad spend", value: "$21,680", detail: "5.95x blended ROAS", systemImage: "megaphone.fill", tint: .pink),
        ExpenseItem(title: "Shipping", value: "$13,240", detail: "$8.14 per order", systemImage: "truck.box.fill", tint: .orange),
        ExpenseItem(title: "Marketplace fees", value: "$13,790", detail: "10.7% blended rate", systemImage: "percent", tint: .blue)
    ]
}
