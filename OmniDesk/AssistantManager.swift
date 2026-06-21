import Foundation
import SwiftUI
import AVFoundation
import UIKit
import PDFKit

struct AssistantAttachment: Identifiable {
    enum Kind: Equatable {
        case image, pdf, text, file

        var icon: String {
            switch self {
            case .image: return "photo.fill"
            case .pdf: return "doc.richtext.fill"
            case .text: return "doc.text.fill"
            case .file: return "paperclip"
            }
        }
    }

    let id = UUID()
    let name: String
    let kind: Kind
    let data: Data?
    let extractedText: String?
}

enum AssistantVisual {
    case product(image: String, name: String, subtitle: String, metrics: [(String, String)], insights: [String], tint: Color)
    case overview(title: String, value: String, change: String, metrics: [(String, String)], tint: Color)
}

struct AssistantAlert: Identifiable {
    let id: String
    let title: String
    let detail: String
    let severity: Severity
    let action: String
    let destination: AppTab
    var isRead: Bool

    enum Severity {
        case urgent, warning, insight

        var color: Color {
            switch self {
            case .urgent: return .red
            case .warning: return .orange
            case .insight: return .blue
            }
        }
    }
}

struct AssistantMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let actionLabel: String?
    let visual: AssistantVisual?
    let attachments: [AssistantAttachment]

    init(
        text: String,
        isUser: Bool,
        actionLabel: String?,
        visual: AssistantVisual? = nil,
        attachments: [AssistantAttachment] = []
    ) {
        self.text = text
        self.isUser = isUser
        self.actionLabel = actionLabel
        self.visual = visual
        self.attachments = attachments
    }
}

@MainActor
final class AssistantManager: ObservableObject {
    static let shared = AssistantManager()

    @Published var name: String
    @Published var messages: [AssistantMessage] = [
        AssistantMessage(text: "Good morning. I found 4 address holds, 9 customers awaiting replies, and 86 labels ready to print. What should we handle first?", isUser: false, actionLabel: nil)
    ]
    @Published var alerts: [AssistantAlert]
    @Published var requestedTab: AppTab?
    @Published var isThinking = false
    @Published var voiceRepliesEnabled = false
    @Published var selectedVoiceName = "Samantha"
    private let speechSynthesizer = AVSpeechSynthesizer()

    private init() {
        name = UserDefaults.standard.string(forKey: "omnidesk.assistantName") ?? "Nova"
        let readIDs = Set(UserDefaults.standard.stringArray(forKey: "omnidesk.readAlerts") ?? [])
        let clearedIDs = Set(UserDefaults.standard.stringArray(forKey: "omnidesk.clearedAlerts") ?? [])
        alerts = Self.defaultAlerts
            .filter { !clearedIDs.contains($0.id) }
            .map {
                var alert = $0
                alert.isRead = readIDs.contains(alert.id)
                return alert
            }
    }

    private static let defaultAlerts = [
        AssistantAlert(id: "shipping-cutoff", title: "4 orders may miss cutoff", detail: "Address validation is blocking label purchase. $514.20 is at risk.", severity: .urgent, action: "Review orders", destination: .orders, isRead: false),
        AssistantAlert(id: "hydration-restock", title: "Hydration Kit stock is low", detail: "12 units remain. At current velocity, stock runs out in 2.4 days.", severity: .warning, action: "Create restock", destination: .dashboard, isRead: false),
        AssistantAlert(id: "priority-inbox", title: "9 customers need replies", detail: "Two priority conversations have waited over one hour.", severity: .warning, action: "Open priority inbox", destination: .chats, isRead: false),
        AssistantAlert(id: "tiktok-roas", title: "TikTok ROAS is climbing", detail: "The Hydration campaign reached 7.2x. A 10% budget increase is supported.", severity: .insight, action: "View campaign", destination: .wallet, isRead: false)
    ]

    var unreadCount: Int { alerts.filter { !$0.isRead }.count }

    func markRead(_ id: String) {
        guard let index = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[index].isRead = true
        persistReadState()
    }

    func clear(_ id: String) {
        markRead(id)
        alerts.removeAll { $0.id == id }
        persistClearedState()
    }

    func clearAll() {
        let allIDs = alerts.map(\.id)
        UserDefaults.standard.set(allIDs, forKey: "omnidesk.clearedAlerts")
        alerts.removeAll()
    }

    func execute(_ alert: AssistantAlert) {
        markRead(alert.id)
        if alert.id == "hydration-restock" {
            messages.append(AssistantMessage(text: "I created a draft restock plan for 120 Hydration Starter Kits, giving you about 24 days of coverage. It is ready for supplier review.", isUser: false, actionLabel: "Review restock plan"))
        }
        requestedTab = alert.destination
    }

    func refreshAlerts() async {
        try? await Task.sleep(for: .milliseconds(650))
    }

    func recordNewOrder(id: String, channel: String, amount: String, customer: String) {
        let alert = AssistantAlert(
            id: "new-order-\(id)-\(UUID().uuidString)",
            title: "New \(channel) order • \(amount)",
            detail: "\(customer) placed order \(id). It is ready for review and fulfillment.",
            severity: .insight,
            action: "Review order",
            destination: .orders,
            isRead: false
        )
        alerts.insert(alert, at: 0)
    }

    func send(_ input: String, attachments: [AssistantAttachment] = []) {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty || !attachments.isEmpty else { return }
        let displayedQuery = query.isEmpty ? "Review \(attachments.count == 1 ? "this file" : "these files") for me." : query
        messages.append(AssistantMessage(text: displayedQuery, isUser: true, actionLabel: nil, attachments: attachments))
        isThinking = true
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            let answer = response(to: displayedQuery, attachments: attachments)
            messages.append(answer)
            isThinking = false
            if voiceRepliesEnabled { speak(answer.text) }
        }
    }

    func attachment(from url: URL) -> AssistantAttachment? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url), data.count <= 15_000_000 else { return nil }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return AssistantAttachment(name: url.lastPathComponent, kind: .image, data: data, extractedText: nil)
        }
        if ext == "pdf" {
            let text = PDFDocument(data: data)?.string
            return AssistantAttachment(name: url.lastPathComponent, kind: .pdf, data: nil, extractedText: text)
        }
        if ["txt", "csv", "json", "md"].contains(ext) {
            return AssistantAttachment(name: url.lastPathComponent, kind: .text, data: nil, extractedText: String(data: data, encoding: .utf8))
        }
        return AssistantAttachment(name: url.lastPathComponent, kind: .file, data: nil, extractedText: nil)
    }

    func rename(_ newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        name = clean
        UserDefaults.standard.set(clean, forKey: "omnidesk.assistantName")
    }

    func speak(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.name.localizedCaseInsensitiveContains(selectedVoiceName)
        } ?? AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }

    private func persistReadState() {
        UserDefaults.standard.set(alerts.filter(\.isRead).map(\.id), forKey: "omnidesk.readAlerts")
    }

    private func persistClearedState() {
        let visible = Set(alerts.map(\.id))
        let cleared = Self.defaultAlerts.map(\.id).filter { !visible.contains($0) }
        UserDefaults.standard.set(cleared, forKey: "omnidesk.clearedAlerts")
    }

    private func response(to query: String, attachments: [AssistantAttachment] = []) -> AssistantMessage {
        let text = query.lowercased()

        if !attachments.isEmpty {
            let readableText = attachments.compactMap(\.extractedText).joined(separator: "\n")
            let detail = readableText.isEmpty
                ? "I attached the file to this conversation and identified its format. Once the secure assistant endpoint is connected, I can inspect its full contents alongside your live store data."
                : "I reviewed the readable content in \(attachments.count == 1 ? attachments[0].name : "\(attachments.count) files"). It contains about \(readableText.split(whereSeparator: \.isWhitespace).count) words. I can summarize it, find order IDs or SKUs, and compare it with your store records."
            return AssistantMessage(
                text: detail,
                isUser: false,
                actionLabel: readableText.isEmpty ? nil : "Summarize key findings",
                visual: .overview(
                    title: "Attachment review",
                    value: "\(attachments.count)",
                    change: attachments.count == 1 ? "file ready" : "files ready",
                    metrics: [("Readable text", readableText.isEmpty ? "Not detected" : "Detected"), ("Max file size", "15 MB")],
                    tint: .blue
                )
            )
        }
        if text == "hi" || text.hasPrefix("hi ") || text.contains("hello") || text.contains("how are you") {
            return AssistantMessage(text: "Hi. I’m doing well and I’m here with you. How is your day going? We can talk normally, or jump into your stores whenever you’re ready.", isUser: false, actionLabel: nil)
        }
        if text.contains("thank") {
            return AssistantMessage(text: "You’re welcome. I’ve got the context from our conversation, so we can keep going from here without starting over.", isUser: false, actionLabel: nil)
        }
        if text.contains("order") && (text.contains("week") || text.contains("new")) {
            return AssistantMessage(
                text: "You have 312 new orders this week. TikTok Shop is leading, and total volume is 18.6% above last week.",
                isUser: false,
                actionLabel: "View weekly orders",
                visual: .overview(title: "Orders this week", value: "312", change: "+18.6%", metrics: [("TikTok", "142"), ("Shopify", "86"), ("Amazon", "84")], tint: .purple)
            )
        }
        if text.contains("winning") || text.contains("best item") || text.contains("top product") {
            return AssistantMessage(
                text: "Your winning item is the Hydration Starter Kit. TikTok Shop is driving most of its growth, but inventory needs attention now.",
                isUser: false,
                actionLabel: "Create restock plan",
                visual: .product(image: "HydrationKit", name: "Hydration Starter Kit", subtitle: "Top seller • TikTok Shop", metrics: [("Revenue", "$3,456"), ("Units", "48"), ("Growth", "+31%"), ("In stock", "12")], insights: ["Increase inventory before the next campaign.", "Keep TikTok creative active while conversion is strong."], tint: .red)
            )
        }
        if text.contains("worst") || text.contains("slow") || text.contains("losing") {
            return AssistantMessage(
                text: "The Canvas Tote is your weakest current product. The main issue is expectation mismatch: customers say it looks larger in the listing than it feels in person.",
                isUser: false,
                actionLabel: "Open product analysis",
                visual: .product(image: "CanvasTote", name: "Canvas Tote", subtitle: "Needs attention • All channels", metrics: [("Revenue", "$336"), ("Units", "8"), ("Conversion", "1.2%"), ("Returns", "9.4%")], insights: ["Add dimensions directly to the first product image.", "Test a Linen Overshirt bundle.", "Reduce prospecting spend until conversion improves."], tint: .orange)
            )
        }
        if text.contains("print") && text.contains("label") {
            return AssistantMessage(text: "I found 38 ready-to-ship Hydration Starter Kit orders. 24 use USPS Ground Advantage and 14 use UPS Ground. The estimated label cost is $284.60. I prepared the batch for your review.", isUser: false, actionLabel: "Review & print 38")
        }
        if text.contains("stock") || text.contains("inventory") {
            return AssistantMessage(text: "Hydration Starter Kit is the only urgent inventory risk: 12 units remain, with 5.1 daily sales velocity. Skin Reset Bundle has 8.4 days of coverage.", isUser: false, actionLabel: "Open inventory risks")
        }
        if text.contains("money") || text.contains("revenue") || text.contains("profit") {
            return AssistantMessage(text: "Revenue is $128,940 for the last 30 days and net profit is $41,820, a 32.4% margin. TikTok is your fastest-growing channel, while Amazon shipping delays are costing an estimated $1,400 in projected margin.", isUser: false, actionLabel: "Open financial analysis")
        }
        if text.contains("message") || text.contains("customer") || text.contains("reply") {
            return AssistantMessage(text: "Nine customers need replies. Jordan Miles and Priya Shah are highest priority because their orders are blocked. I can prepare replies using their order and shipping context.", isUser: false, actionLabel: "Draft priority replies")
        }
        return AssistantMessage(text: "I searched orders, customers, fulfillment, chats, payouts, ads, and store health. I can answer questions about performance or prepare actions such as label batches, customer replies, exports, and restock lists.", isUser: false, actionLabel: "Show suggested actions")
    }
}
