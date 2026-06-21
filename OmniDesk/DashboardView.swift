import SwiftUI
import UIKit
import Clerk
import UniformTypeIdentifiers

private extension Notification.Name {
    static let shipDemonScrollActivity = Notification.Name("shipDemonScrollActivity")
}

enum AppTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case orders = "Orders"
    case chats = "Chats"
    case assistant = "Assistant"
    case wallet = "Wallet"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .orders: return "shippingbox.fill"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .assistant: return "sparkles"
        case .wallet: return "creditcard.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct DashboardView: View {
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var workspace: UserWorkspace
    @State private var selectedTab: AppTab = .dashboard
    @StateObject private var assistant = AssistantManager.shared
    @State private var dockVisible = true
    @State private var dockHideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if workspace.isRealAccount && !workspace.profile.isComplete {
                WorkspaceOnboardingView()
            } else if workspace.isRealAccount && !workspace.hasStores && selectedTab != .settings && selectedTab != .assistant {
                EmptyWorkspaceView(openSettings: { selectedTab = .settings })
            } else {
                switch selectedTab {
                case .dashboard: DashboardHome()
                case .orders: OrdersView()
                case .chats: ChatsView()
                case .assistant: AssistantView()
                case .wallet: WalletView()
                case .settings: SettingsView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if dockVisible {
                BottomDock(selection: $selectedTab, onInteraction: showDock)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: selectedTab)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: dockVisible)
        .onAppear { showDock() }
        .onDisappear { dockHideTask?.cancel() }
        .onChange(of: selectedTab) { _, _ in showDock() }
        .onReceive(NotificationCenter.default.publisher(for: .shipDemonScrollActivity)) { _ in
            showDock()
        }
        .onChange(of: assistant.requestedTab) { _, destination in
            guard let destination else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selectedTab = destination
            }
            assistant.requestedTab = nil
        }
        .task(id: clerk.user?.id) {
            workspace.configure(with: clerk.user)
        }
    }

    private func showDock() {
        dockHideTask?.cancel()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            dockVisible = true
        }
        dockHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    dockVisible = false
                }
            }
        }
    }
}

private struct InsightDetail: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let value: String
    let rows: [(String, String)]
    let recommendations: [String]
}

private struct WorkspaceOnboardingView: View {
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var workspace: UserWorkspace
    @State private var name = ""
    @State private var phone = ""
    @State private var company = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.green)
                    Text("Finish your profile")
                        .font(.system(size: 30, weight: .semibold))
                    Text("These details personalize Settings, store ownership, notifications, and customer-facing operations for your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        TextField("Full name", text: $name)
                        TextField("Phone number", text: $phone).keyboardType(.phonePad)
                        TextField("Company name", text: $company)
                    }
                    .textFieldStyle(.roundedBorder)

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving { ProgressView() } else { Text("Complete setup") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Ship Demon")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                name = workspace.profile.name
                phone = workspace.profile.phone
                company = workspace.profile.company
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
            if let user = clerk.user {
                _ = try await user.update(.init(firstName: parts.first, lastName: parts.count > 1 ? parts[1] : nil))
                if user.phoneNumbers.isEmpty, phone.hasPrefix("+") {
                    _ = try await user.createPhoneNumber(phone)
                }
            }
            workspace.saveProfile(WorkspaceProfile(
                name: name,
                email: clerk.user?.primaryEmailAddress?.emailAddress ?? workspace.profile.email,
                phone: phone,
                company: company
            ))
        } catch {
            errorMessage = "Your profile was saved locally. Phone verification can be completed in account security."
            workspace.saveProfile(WorkspaceProfile(name: name, email: workspace.profile.email, phone: phone, company: company))
        }
        isSaving = false
    }
}

private struct EmptyWorkspaceView: View {
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "storefront.circle.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(Theme.green)
                Text("Connect your first store")
                    .font(.title2.weight(.semibold))
                Text("Your dashboard stays empty until Shopify, TikTok Shop, Amazon, or Walmart is connected. Every account has its own stores and data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open store connections", action: openSettings)
                    .buttonStyle(PremiumButtonStyle())
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationTitle("Ship Demon")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum OrderBrowseMode: String, CaseIterable {
    case orders = "Orders"
    case items = "Items"
}

private enum OrderSort: String, CaseIterable {
    case newest = "Newest"
    case value = "Highest value"
    case priority = "Priority first"
}

private struct ItemRollup: Identifiable {
    let name: String
    let orders: [Order]
    var id: String { name }
    var units: Int { orders.reduce(0) { $0 + $1.itemCount } }
    var revenue: Double {
        orders.reduce(0) {
            $0 + Double($1.total.filter { "0123456789.".contains($0) })!
        }
    }
}

private struct DashboardHome: View {
    @State private var selectedRange = "30D"
    @State private var toast: String?
    @State private var detail: InsightDetail?
    @State private var showingTracker = false

    var body: some View {
        Screen(title: "Dashboard", subtitle: "Your commerce business, in one place", toast: toast) {
            VStack(spacing: 16) {
                FulfillmentPulse(
                    showTracker: { showingTracker = true },
                    showDetail: { detail = $0 }
                )
                MetricGrid(showDetail: { detail = $0 })
                RevenueChart(selectedRange: $selectedRange, showDetail: { detail = $0 })
                ProductPerformanceSection()
                ChannelPerformanceCard(showDetail: { detail = $0 })
                ActionQueue(showToast: showToast, showDetail: { detail = $0 })
                RecentOrdersCard(showToast: showToast)
            }
        } trailing: { EmptyView() }
        .sheet(item: $detail) { detail in
            InsightDetailView(detail: detail, showToast: showToast)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTracker) {
            ShipmentTrackerView()
                .presentationDetents([.large])
        }
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

private struct OrdersView: View {
    @State private var browseMode: OrderBrowseMode = .orders
    @State private var selectedChannels: Set<SalesChannel> = []
    @State private var selectedStatus: OrderState?
    @State private var searchText = ""
    @State private var selectedOrder: Order?
    @State private var toast: String?
    @State private var selectedOrderIDs: Set<String> = []
    @State private var showingOrderStats = false
    @State private var selectedSort: OrderSort = .newest
    @State private var showingTracker = false
    @State private var showingPrintCenter = false

    private var filteredOrders: [Order] {
        let matches = DemoData.orders.filter { order in
            let channelMatches = selectedChannels.isEmpty || selectedChannels.contains(order.channel)
            let statusMatches = selectedStatus == nil || order.state == selectedStatus
            let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
            let text = "\(order.id) \(order.customer) \(order.email) \(order.items)".lowercased()
            return channelMatches && statusMatches && (query.isEmpty || text.contains(query))
        }
        switch selectedSort {
        case .newest: return matches
        case .value:
            return matches.sorted {
                Double($0.total.filter { "0123456789.".contains($0) })! >
                Double($1.total.filter { "0123456789.".contains($0) })!
            }
        case .priority:
            return matches.sorted {
                let firstRank = [$0.state == .hold, $0.state == .message, $0.state == .ready].firstIndex(of: true) ?? 3
                let secondRank = [$1.state == .hold, $1.state == .message, $1.state == .ready].firstIndex(of: true) ?? 3
                return firstRank < secondRank
            }
        }
    }

    private var itemRollups: [ItemRollup] {
        Dictionary(grouping: filteredOrders, by: \.items)
            .map { ItemRollup(name: $0.key, orders: $0.value) }
            .sorted { $0.units > $1.units }
    }

    var body: some View {
        Screen(title: "Orders", subtitle: "\(DemoData.orders.count) orders across all stores", toast: toast) {
            VStack(spacing: 14) {
                OrderFilterWorkspace(
                    browseMode: $browseMode,
                    searchText: $searchText,
                    selectedChannels: $selectedChannels,
                    selectedStatus: $selectedStatus,
                    selectedSort: $selectedSort,
                    resultCount: filteredOrders.count
                )
                Button { showingOrderStats = true } label: { OrderSummaryStrip() }
                    .buttonStyle(PressableButtonStyle())
                if browseMode == .orders {
                    selectionToolbar
                    if !selectedOrderIDs.isEmpty {
                        BulkOrderActions(selectedCount: selectedOrderIDs.count, showToast: showToast)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(filteredOrders) { order in
                            OrderCard(
                                order: order,
                                selected: selectedOrderIDs.contains(order.id),
                                toggleSelection: { toggleSelection(order.id) },
                                openOrder: { selectedOrder = order }
                            )
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(itemRollups) { item in
                            ItemRollupCard(item: item) {
                                browseMode = .orders
                                searchText = item.name
                            }
                        }
                    }
                }
            }
        } trailing: {
            HStack(spacing: 14) {
                Button {
                    Task {
                        do {
                            try await NotificationManager.shared.scheduleTestOrder()
                            showToast("Test notification arrives in 2 seconds.")
                        } catch {
                            showToast("Enable notifications in Settings first.")
                        }
                    }
                } label: {
                    Image(systemName: "bell.badge.fill")
                }
                Button { showingTracker = true } label: {
                    Image(systemName: "location.viewfinder")
                }
                Button { showingPrintCenter = true } label: {
                    Image(systemName: "printer.fill")
                }
                Menu {
                    Button(selectedOrderIDs.count == filteredOrders.count ? "Clear selection" : "Select all") {
                        if selectedOrderIDs.count == filteredOrders.count {
                            selectedOrderIDs.removeAll()
                        } else {
                            selectedOrderIDs = Set(filteredOrders.map(\.id))
                        }
                    }
                    Button("Open tracker", systemImage: "location.viewfinder") { showingTracker = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $selectedOrder) { order in
            OrderDetailView(order: order, showToast: showToast)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingOrderStats) {
            OrderAnalyticsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTracker) {
            ShipmentTrackerView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingPrintCenter) {
            PrintCenterView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var selectionToolbar: some View {
        Group {
            if !selectedOrderIDs.isEmpty {
                VStack(spacing: 10) {
                    HStack {
                        Button(selectedOrderIDs.count == filteredOrders.count ? "Clear all" : "Select all") {
                            if selectedOrderIDs.count == filteredOrders.count {
                                selectedOrderIDs.removeAll()
                            } else {
                                selectedOrderIDs = Set(filteredOrders.map(\.id))
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(selectedOrderIDs.count) selected").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(Array(Set(filteredOrders.map(\.items))).sorted(), id: \.self) { sku in
                                Button(sku) {
                                    selectedOrderIDs = Set(filteredOrders.filter { $0.items == sku }.map(\.id))
                                }
                            }
                        } label: {
                            Label("Select by SKU", systemImage: "barcode")
                        }
                        .buttonStyle(.bordered)
                        Menu {
                            Button("Ready to ship") { selectStatus(.ready) }
                            Button("Needs reply") { selectStatus(.message) }
                            Button("On hold") { selectStatus(.hold) }
                            Button("Amazon orders") { selectChannel(.amazon) }
                            Button("TikTok orders") { selectChannel(.tiktok) }
                        } label: {
                            Label("Category", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .premiumCard()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func toggleSelection(_ id: String) {
        withAnimation(.snappy) {
            if selectedOrderIDs.contains(id) { selectedOrderIDs.remove(id) } else { selectedOrderIDs.insert(id) }
        }
    }

    private func selectStatus(_ status: OrderState) {
        selectedOrderIDs = Set(filteredOrders.filter { $0.state == status }.map(\.id))
    }

    private func selectChannel(_ channel: SalesChannel) {
        selectedOrderIDs = Set(filteredOrders.filter { $0.channel == channel }.map(\.id))
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

private struct ChatsView: View {
    @State private var conversations = DemoData.conversations
    @State private var selectedChannel: SalesChannel = .all
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?
    @State private var showingBulkComposer = false
    @State private var toast: String?

    private var filteredConversations: [Conversation] {
        conversations.filter { conversation in
            let channelMatches = selectedChannel == .all || conversation.channel == selectedChannel
            let query = searchText.lowercased()
            let text = "\(conversation.customer) \(conversation.orderID) \(conversation.preview)".lowercased()
            return channelMatches && (query.isEmpty || text.contains(query))
        }
    }

    var body: some View {
        Screen(title: "Chats", subtitle: "One inbox for every marketplace", toast: toast) {
            VStack(spacing: 14) {
                InboxCommandCenter(showBulkComposer: { showingBulkComposer = true })
                SearchField(text: $searchText, prompt: "Search messages or customers")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([SalesChannel.all, .shopify, .tiktok, .amazon]) { channel in
                            FilterPill(title: channel.shortName, selected: selectedChannel == channel) {
                                withAnimation(.snappy) { selectedChannel = channel }
                            }
                        }
                    }
                }
                InboxSummary()

                LazyVStack(spacing: 8) {
                    ForEach(filteredConversations) { conversation in
                        Button { selectedConversation = conversation } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
        } trailing: {
            Button { showToast("All messages marked as read.") } label: {
                Image(systemName: "checkmark.circle")
            }
        }
        .sheet(item: $selectedConversation) { conversation in
            ChatThreadView(conversation: conversation, showToast: showToast)
        }
        .sheet(isPresented: $showingBulkComposer) {
            BulkMessageView(showToast: showToast)
                .presentationDetents([.large])
        }
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

private struct WalletView: View {
    @State private var selectedRange = "30D"
    @State private var toast: String?
    @State private var detail: InsightDetail?

    var body: some View {
        Screen(title: "Wallet", subtitle: "Cash flow, expenses, and return on spend", toast: toast) {
            VStack(spacing: 16) {
                FinancialPulseHeader()
                WalletBalanceCard(showToast: showToast) {
                    detail = InsightDetail(title: "Label wallet", subtitle: "Funding and shipping-label activity", value: "$2,840.60", rows: [("Available balance", "$2,840.60"), ("Labels purchased this month", "$13,240"), ("Average label", "$8.14"), ("Automatic top-up", "Off"), ("Estimated shipments", "349")], recommendations: ["Enable automatic top-up below $500 to avoid fulfillment interruptions.", "UPS Ground is 8% less expensive than your current blended rate."])
                }
                FinancialMetricGrid(showDetail: { detail = $0 })
                ProfitChart(selectedRange: $selectedRange, showDetail: { detail = $0 })
                PendingPayoutsCard(showDetail: { detail = $0 })
                ExpenseBreakdownCard(showDetail: { detail = $0 })
                ROICard(showDetail: { detail = $0 })
            }
        } trailing: {
            Button { showToast("Financial report exported.") } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .sheet(item: $detail) { detail in
            InsightDetailView(detail: detail, showToast: showToast)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var workspace: UserWorkspace
    @State private var notifications = true
    @State private var autoBuyLabels = false
    @State private var showingAddStore = false
    @State private var toast: String?
    @State private var showingEditProfile = false
    @State private var showingCompanyDetails = false
    @State private var showingIntegrationAdmin = false
    @StateObject private var notificationsManager = NotificationManager.shared

    private var canAccessAdministration: Bool {
        workspace.isRealAccount
            ? workspace.isDeveloper
            : auth.currentEmail.lowercased() == "demo@omnidesk.app"
    }

    var body: some View {
        Screen(title: "Settings", subtitle: "Profile, stores, team, and preferences", toast: toast) {
            VStack(spacing: 16) {
                SettingsControlHeader()
                ProfileCard { showingEditProfile = true }
                StoresCard(showingAddStore: $showingAddStore, showToast: showToast)
                SettingsGroup(title: "Operations") {
                    ToggleRow(icon: "bell.fill", title: "Order notifications", subtitle: notificationSubtitle, isOn: $notifications)
                        .onChange(of: notifications) { _, enabled in
                            guard enabled else { return }
                            Task {
                                let granted = await notificationsManager.requestAuthorization()
                                showToast(granted ? "Order notifications enabled." : "Notification permission was not granted.")
                            }
                        }
                    Divider()
                    ToggleRow(icon: "printer.fill", title: "Auto-purchase labels", subtitle: "Buy the lowest eligible shipping rate", isOn: $autoBuyLabels)
                    Divider()
                    SettingsRow(icon: "person.2.fill", title: "Team members", detail: "4 members", tint: .indigo) {
                        showToast("Team management opened.")
                    }
                }
                SettingsGroup(title: "Business") {
                    SettingsRow(
                        icon: "building.2.fill",
                        title: "Company details",
                        detail: workspace.isRealAccount
                            ? (workspace.profile.company.isEmpty ? "Add company details" : workspace.profile.company)
                            : "Northstar Goods LLC",
                        tint: .blue
                    ) {
                        showingCompanyDetails = true
                    }
                    Divider()
                    SettingsRow(icon: "creditcard.fill", title: "Billing & plan", detail: "Scale plan", tint: .green) {
                        showToast("Billing opened.")
                    }
                    Divider()
                    SettingsRow(icon: "shield.lefthalf.filled", title: "Security", detail: "2FA enabled", tint: .orange) {
                        showToast("Security settings opened.")
                    }
                }
                if canAccessAdministration {
                    SettingsGroup(title: "Administration") {
                        SettingsRow(icon: "key.horizontal.fill", title: "Integration vault", detail: "Keys, stores, and services", tint: .green) {
                            showingIntegrationAdmin = true
                        }
                    }
                }
                Button(role: .destructive) {
                    Task {
                        if Clerk.shared.user != nil {
                            try? await Clerk.shared.signOut()
                        }
                        auth.signOut()
                    }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("Ship Demon 1.0 • Data is encrypted in transit and at rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        } trailing: {
            Button { showToast("Profile saved.") } label: {
                Text("Save").fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingAddStore) {
            AddStoreView(showToast: showToast)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(showToast: showToast)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingCompanyDetails) {
            CompanyDetailsView(showToast: showToast)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingIntegrationAdmin) {
            IntegrationAdminView()
        }
        .task {
            await notificationsManager.refreshAuthorizationStatus()
            notifications = notificationsManager.authorizationStatus == .authorized
        }
    }

    private var notificationSubtitle: String {
        switch notificationsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Enabled for new orders, holds, and messages"
        case .denied: return "Disabled in iOS Settings"
        default: return "Push alerts for new orders and holds"
        }
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

// MARK: - Dashboard

private struct HealthBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.mint)
                Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(Theme.green)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Everything is running smoothly").font(.subheadline.weight(.bold))
                Text("4 stores synced • Updated 2 min ago").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("99.8%").font(.subheadline.weight(.heavy)).foregroundStyle(Theme.green)
        }
        .premiumCard()
    }
}

private struct MetricGrid: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(spacing: 11) {
            if let revenue = DemoData.metrics.first {
                Button { showDetail(metricDetail(revenue)) } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("OVERALL REVENUE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.16), in: Circle())
                        }
                        AnimatedCurrencyText(value: 128_940, fontSize: 38, color: .white)
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach([0.26, 0.38, 0.31, 0.52, 0.46, 0.68, 0.61, 0.84, 0.74, 0.92], id: \.self) { value in
                                Capsule()
                                    .fill(.white.opacity(0.28 + value * 0.55))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 13 + value * 42)
                            }
                        }
                        .frame(height: 56, alignment: .bottom)
                        HStack {
                            Label("+18.4%", systemImage: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Text("than last month").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(18)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.blue.opacity(0.22), radius: 24, y: 12)
                }
                .buttonStyle(PressableButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(DemoData.metrics.dropFirst())) { metric in
                        Button { showDetail(metricDetail(metric)) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: metric.systemImage).foregroundStyle(metric.accent)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                Text(metric.value).font(.title3.weight(.heavy)).minimumScaleFactor(0.75)
                                Text(metric.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(metric.detail).font(.caption2).foregroundStyle(metric.accent)
                            }
                            .frame(width: 145, alignment: .leading)
                            .premiumCard()
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
    }

    private func metricDetail(_ metric: Metric) -> InsightDetail {
        switch metric.title {
        case "Gross revenue":
            return InsightDetail(title: "Gross revenue", subtitle: "Sales before refunds, fees, and expenses", value: "$128,940", rows: [("Today", "$6,842"), ("Yesterday", "$5,914"), ("Last 7 days", "$32,480"), ("Last 30 days", "$128,940"), ("Refunds", "-$2,184")], recommendations: ["TikTok Shop is growing 24% faster than last month.", "Friday and Sunday are your strongest conversion days."])
        case "Open orders":
            return InsightDetail(title: "Open orders", subtitle: "Fulfillment workload across every store", value: "342", rows: [("Amazon", "84"), ("TikTok Shop", "142"), ("Shopify", "116"), ("Ready for labels", "86"), ("On hold", "4")], recommendations: ["Batch the 86 ready orders by carrier to reduce handling time.", "Four address holds are delaying same-day fulfillment."])
        case "Net profit":
            return InsightDetail(title: "Net profit", subtitle: "Revenue after product, ad, shipping, and platform costs", value: "$41,820", rows: [("Gross revenue", "$128,940"), ("Product costs", "-$38,410"), ("Ad spend", "-$21,680"), ("Shipping & fees", "-$27,030"), ("Margin", "32.4%")], recommendations: ["Your margin improved 2.8 points month over month.", "Amazon fees are 1.4 points above your blended target."])
        default:
            return InsightDetail(title: "Customer messages", subtitle: "Unified response performance", value: "27", rows: [("Unread", "4"), ("Needs first reply", "9"), ("Average reply", "8 min"), ("Resolved today", "31"), ("Satisfaction", "96%")], recommendations: ["Two priority buyers have waited longer than one hour.", "Saved replies could reduce response time by about 18%."])
        }
    }
}

private struct FulfillmentPulse: View {
    let showTracker: () -> Void
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionTitle(kicker: "Today", title: "Order operations")
                Spacer()
                Button(action: showTracker) {
                    Label("Tracker", systemImage: "location.viewfinder")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    showDetail(InsightDetail(
                        title: "Total orders",
                        subtitle: "Today’s order volume across connected stores",
                        value: "74",
                        rows: [("Shopify", "24"), ("TikTok Shop", "30"), ("Amazon", "20"), ("Yesterday", "61"), ("Change", "+21%")],
                        recommendations: ["TikTok Shop generated 41% of today’s orders.", "Order volume is pacing above the 30-day daily average."]
                    ))
                } label: {
                    OperationMetricCard(title: "Total orders", value: "74", detail: "+21% vs yesterday", tint: Theme.blue, style: .bars)
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    showDetail(InsightDetail(
                        title: "Fulfilled today",
                        subtitle: "Orders completed before today’s carrier cutoffs",
                        value: "58",
                        rows: [("Completion", "78%"), ("UPS", "24"), ("USPS", "21"), ("Amazon Shipping", "13"), ("Remaining", "16")],
                        recommendations: ["Six remaining orders only need labels.", "Complete four address holds before the final USPS pickup."]
                    ))
                } label: {
                    OperationMetricCard(title: "Fulfilled today", value: "58", detail: "78% complete", tint: Theme.green, style: .ring)
                }
                .buttonStyle(PressableButtonStyle())
            }

            Button {
                showDetail(InsightDetail(
                    title: "Pending orders",
                    subtitle: "Orders still requiring fulfillment action",
                    value: "16",
                    rows: [("Need labels", "6"), ("Address holds", "4"), ("Awaiting stock", "3"), ("Customer reply", "2"), ("Payment review", "1")],
                    recommendations: ["Print the six ready labels as one carrier batch.", "Contact the four customers with address issues before cutoff."]
                ))
            } label: {
                OperationMetricCard(title: "Pending orders", value: "16", detail: "6 need labels • 4 on hold", tint: .orange, style: .grid)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

private struct OperationMetricCard: View {
    enum Style { case bars, ring, grid }
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(value).font(.system(size: 27, weight: .semibold))
                    Text(detail).font(.caption2).foregroundStyle(tint)
                }
                Spacer(minLength: 8)
                chart
            }
        }
        .premiumCard()
    }

    @ViewBuilder
    private var chart: some View {
        switch style {
        case .bars:
            HStack(alignment: .bottom, spacing: 3) {
                ForEach([12, 20, 15, 28, 23, 35], id: \.self) { height in
                    Capsule().fill(tint.opacity(Double(height) / 45 + 0.18)).frame(width: 5, height: CGFloat(height))
                }
            }
            .frame(width: 48, height: 40, alignment: .bottom)
        case .ring:
            ZStack {
                Circle().stroke(tint.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("78").font(.caption2.weight(.semibold)).foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)
        case .grid:
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(9), spacing: 4), count: 6), spacing: 4) {
                ForEach(0..<18, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < 12 ? tint.opacity(0.82) : tint.opacity(0.14))
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 74)
        }
    }
}

private struct ProductPerformanceSection: View {
    @State private var detailMode: ProductDetailMode?

    var body: some View {
        VStack(spacing: 12) {
            ProductSnapshotCard(
                kicker: "Products",
                title: "Top selling",
                name: "Hydration Starter Kit",
                image: "HydrationKit",
                value: "48 sold • $3,456",
                insight: "+31% week over week",
                tint: Theme.green
            ) { detailMode = .best }

            ProductSnapshotCard(
                kicker: "Needs attention",
                title: "Lowest performing",
                name: "Canvas Tote",
                image: "CanvasTote",
                value: "8 sold • $336",
                insight: "Conversion down 22%",
                tint: .orange
            ) { detailMode = .worst }
        }
        .sheet(item: $detailMode) { mode in
            ProductInsightsView(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private enum ProductDetailMode: String, Identifiable {
    case best, worst
    var id: String { rawValue }
}

private struct ProductSnapshotCard: View {
    let kicker: String
    let title: String
    let name: String
    let image: String
    let value: String
    let insight: String
    let tint: Color
    let viewMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionTitle(kicker: kicker, title: title)
                Spacer()
                Button("View more", action: viewMore)
                    .font(.caption.weight(.semibold))
            }
            HStack(spacing: 11) {
                Image(image).resizable().scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(value).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(insight).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            }
        }
        .premiumCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: viewMore)
    }
}

private struct ProductInsightsView: View {
    let mode: ProductDetailMode
    @Environment(\.dismiss) private var dismiss

    private var products: [(String, String, String, String)] {
        if mode == .best {
            return [
                ("Hydration Starter Kit", "48 sold", "$3,456", "HydrationKit"),
                ("Skin Reset Bundle", "39 sold", "$5,421", "SkinReset"),
                ("Linen Overshirt", "31 sold", "$3,658", "LinenOvershirt"),
                ("Travel Organizer", "24 sold", "$1,411", "TravelOrganizer"),
                ("Wellness Essentials", "19 sold", "$1,834", "WellnessEssentials")
            ]
        }
        return [
            ("Canvas Tote", "8 sold", "$336", "CanvasTote"),
            ("Everyday Cap", "11 sold", "$418", "EverydayCap"),
            ("Ceramic Dinner Set", "12 sold", "$2,962", "CeramicDinner"),
            ("Travel Organizer", "14 sold", "$823", "TravelOrganizer"),
            ("Wellness Essentials", "16 sold", "$1,544", "WellnessEssentials")
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(products.enumerated()), id: \.offset) { index, product in
                        HStack(spacing: 11) {
                            Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                                .frame(width: 25, height: 25).background(Theme.softBlue, in: Circle())
                            Image(product.3).resizable().scaledToFill()
                                .frame(width: 43, height: 43).clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.0).font(.subheadline.weight(.medium))
                                Text(product.1).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.2).font(.subheadline.weight(.semibold))
                        }
                        .premiumCard()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(kicker: "AI analysis", title: mode == .best ? "Why these are winning" : "What is holding them back")
                        Text(mode == .best
                             ? "Strong TikTok discovery, repeat buyers, and bundle-friendly pricing are driving performance. Protect inventory, expand winning creatives, and test a 10% price lift on the highest-converting traffic."
                             : "Low conversion is tied to unclear sizing, weaker imagery, and broad ad traffic. Add dimensions to product media, bundle slow items with winners, narrow targeting, and pause placements below 2x ROAS.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .premiumCard()
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle(mode == .best ? "Top 5 products" : "Lowest 5 products")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct RevenueChart: View {
    @Binding var selectedRange: String
    let showDetail: (InsightDetail) -> Void
    private let values: [CGFloat] = [0.32, 0.48, 0.40, 0.65, 0.58, 0.80, 0.72, 0.94, 0.78, 0.88]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(kicker: "Revenue", title: "$128,940")
                Spacer()
                MiniRangePicker(selection: $selectedRange)
            }
            ChartBars(
                values: values,
                labels: ["Jun 4", "Jun 5", "Jun 6", "Jun 7", "Jun 8", "Jun 9", "Jun 10", "Jun 11", "Jun 12", "Today"],
                amounts: ["$3,840", "$5,220", "$4,610", "$7,180", "$6,440", "$9,210", "$8,060", "$11,940", "$9,880", "$10,760"],
                tint: Theme.green
            )
            HStack {
                Label("+18.4%", systemImage: "arrow.up.right").foregroundStyle(Theme.green)
                Text("vs previous period").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
        }
        .premiumCard()
    }
}

private struct ChannelPerformanceCard: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(kicker: "Operations", title: "Store health")
                Spacer()
                Text("84").font(.title2.weight(.bold)).foregroundStyle(Theme.green)
                Text("/ 100").font(.caption).foregroundStyle(.secondary)
            }
            HealthStoreRow(channel: .shopify, score: 94, trend: "+18%", detail: "Strong growth • 1 late order") {
                showDetail(channelDetail(.shopify))
            }
            HealthStoreRow(channel: .tiktok, score: 86, trend: "+9%", detail: "Healthy • 3 policy warnings") {
                showDetail(channelDetail(.tiktok))
            }
            HealthStoreRow(channel: .amazon, score: 62, trend: "-30%", detail: "12 violations • 30 late orders") {
                showDetail(channelDetail(.amazon))
            }
        }
        .premiumCard()
    }

    private func channelDetail(_ channel: SalesChannel) -> InsightDetail {
        let amount = channel == .shopify ? "$61,240" : channel == .tiktok ? "$42,700" : "$24,990"
        let score = channel == .shopify ? "92 / 100" : channel == .tiktok ? "86 / 100" : "71 / 100"
        return InsightDetail(title: "\(channel.rawValue) performance", subtitle: "Revenue, fulfillment health, and conversion signals", value: score, rows: [("Revenue", amount), ("Orders today", channel == .amazon ? "20" : channel == .tiktok ? "30" : "24"), ("Conversion", channel == .amazon ? "2.8%" : "4.6%"), ("Late shipment rate", channel == .amazon ? "4.2%" : "1.1%"), ("Refund rate", channel == .amazon ? "3.1%" : "1.8%")], recommendations: channel == .amazon ? ["Amazon performance is held back by four late shipments.", "Move popular SKUs to FBA or shorten handling time.", "Resolve address holds before the next carrier cutoff."] : ["Your fulfillment health is above target.", "Increase inventory on the two fastest-selling SKUs."])
    }
}

private struct HealthStoreRow: View {
    let channel: SalesChannel
    let score: Int
    let trend: String
    let detail: String
    let action: () -> Void

    private var tint: Color {
        score >= 85 ? Theme.green : score >= 70 ? .orange : .red
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ChannelIcon(channel: channel, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(channel.shortName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(trend)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trend.hasPrefix("-") ? Color.red : Theme.green)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(Theme.softGray)
                            .overlay(alignment: .leading) {
                                Capsule().fill(tint)
                                    .frame(width: geometry.size.width * CGFloat(score) / 100)
                            }
                    }
                    .frame(height: 6)
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(score)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34)
            }
            .padding(12)
            .background(Theme.softGray.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct ActionQueue: View {
    let showToast: (String) -> Void
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(kicker: "Priority", title: "Needs attention")
            ActionRow(icon: "printer.fill", tint: .blue, title: "Print 86 labels", detail: "Rates are ready") {
                showDetail(InsightDetail(title: "Labels ready to print", subtitle: "Orders grouped by carrier and service", value: "86", rows: [("USPS Ground Advantage", "38 labels"), ("UPS Ground", "27 labels"), ("USPS Priority", "14 labels"), ("DHL Express", "7 labels"), ("Estimated cost", "$712.40")], recommendations: ["Select a carrier group to review individual orders.", "Printing in carrier batches saves approximately 22 minutes."]))
            }
            ActionRow(icon: "bubble.left.fill", tint: .pink, title: "Reply to 9 customers", detail: "Oldest waiting 2h 18m") {
                showDetail(InsightDetail(title: "Customers awaiting replies", subtitle: "Sorted by wait time and marketplace priority", value: "9", rows: [("Jordan Miles", "2h 18m • TikTok"), ("Priya Shah", "1h 42m • Amazon"), ("Theo Walker", "54m • Shopify"), ("First-time buyers", "6"), ("Order issues", "3")], recommendations: ["Reply to marketplace cases before general questions.", "Use the shipping-delay saved reply for three conversations."]))
            }
            ActionRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Resolve 4 address holds", detail: "Carrier validation failed") {
                showDetail(InsightDetail(title: "Address holds", subtitle: "Orders blocked from label purchase", value: "4", rows: [("#AMZ-71854", "Missing apartment"), ("#TT-89011", "Postal code mismatch"), ("#AMZ-72014", "Street not recognized"), ("#TT-89025", "Unit required"), ("Value at risk", "$514.20")], recommendations: ["Message all four customers from the Chats tab.", "Enable automatic address validation at checkout."]))
            }
        }
        .premiumCard()
    }
}

private struct RecentOrdersCard: View {
    let showToast: (String) -> Void
    @State private var selectedOrder: Order?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(kicker: "Live", title: "Recent orders")
            ForEach(DemoData.orders.prefix(3)) { order in
                Button { selectedOrder = order } label: {
                    CompactOrderRow(order: order)
                }
                .buttonStyle(.plain)
                if order.id != DemoData.orders.prefix(3).last?.id { Divider() }
            }
        }
        .premiumCard()
        .sheet(item: $selectedOrder) { order in
            OrderDetailView(order: order, showToast: showToast)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Orders

private struct StatusFilter: View {
    @Binding var selectedStatus: OrderState?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(title: "Any status", selected: selectedStatus == nil) {
                    selectedStatus = nil
                }
                ForEach(OrderState.allCases) { status in
                    FilterPill(title: status.rawValue, selected: selectedStatus == status) {
                        selectedStatus = status
                    }
                }
            }
        }
    }
}

private struct OrderSummaryStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            SummaryCell(value: "342", label: "Open")
            SummaryCell(value: "86", label: "Ready")
            SummaryCell(value: "4", label: "Holds")
            SummaryCell(value: "$41k", label: "Value")
        }
    }
}

private struct BulkOrderActions: View {
    let selectedCount: Int
    let showToast: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { showToast("\(selectedCount == 0 ? 86 : selectedCount) labels queued.") } label: {
                Label(selectedCount == 0 ? "Print ready" : "Print \(selectedCount)", systemImage: "printer.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PremiumButtonStyle())
            Menu {
                Button("Change status", systemImage: "checkmark.circle") { showToast("Status editor opened.") }
                Button("Assign carrier", systemImage: "truck.box") { showToast("Carrier selector opened.") }
                Button("Export CSV", systemImage: "square.and.arrow.up") { showToast("Order export prepared.") }
                Button("Message customers", systemImage: "bubble.left") { showToast("Bulk message composer opened.") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct OrderCard: View {
    let order: Order
    let selected: Bool
    let toggleSelection: () -> Void
    let openOrder: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Button(action: toggleSelection) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.blue : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            ZStack(alignment: .bottomTrailing) {
                Image(order.productImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                ChannelIcon(channel: order.channel, size: 19)
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(order.items)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(order.total).font(.subheadline.weight(.semibold))
                }
                HStack {
                    Text(order.id).font(.caption).foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(order.customer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    StatusPill(state: order.state)
                    Text(order.date).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openOrder)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.ink.opacity(0.045), radius: 10, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Theme.blue.opacity(0.8) : .clear, lineWidth: 1.5)
        )
    }
}

private struct OrderFilterWorkspace: View {
    @Binding var browseMode: OrderBrowseMode
    @Binding var searchText: String
    @Binding var selectedChannels: Set<SalesChannel>
    @Binding var selectedStatus: OrderState?
    @Binding var selectedSort: OrderSort
    let resultCount: Int

    var body: some View {
        VStack(spacing: 13) {
            Picker("Browse orders", selection: $browseMode) {
                ForEach(OrderBrowseMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            SearchField(text: $searchText, prompt: "Order, customer, item, or SKU")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { selectedChannels.removeAll() }
                    } label: {
                        Text("All").font(.caption.weight(.semibold))
                            .foregroundStyle(selectedChannels.isEmpty ? .white : Theme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 35)
                            .background(selectedChannels.isEmpty ? Theme.ink : Theme.softGray, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    ForEach([SalesChannel.shopify, .tiktok, .amazon, .walmart]) { channel in
                        Button {
                            withAnimation(.snappy) {
                                if selectedChannels.contains(channel) {
                                    selectedChannels.remove(channel)
                                } else {
                                    selectedChannels.insert(channel)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if channel != .all { ChannelIcon(channel: channel, size: 23) }
                                Text(channel.shortName).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(selectedChannels.contains(channel) ? .white : Theme.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 35)
                            .background(selectedChannels.contains(channel) ? Theme.ink : Theme.softGray, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Button("Any status") { selectedStatus = nil }
                    ForEach(OrderState.allCases) { status in
                        Button(status.rawValue) { selectedStatus = status }
                    }
                } label: {
                    Label(selectedStatus?.rawValue ?? "Any status", systemImage: "line.3.horizontal.decrease")
                        .frame(maxWidth: .infinity)
                }
                Menu {
                    ForEach(OrderSort.allCases, id: \.self) { sort in
                        Button(sort.rawValue) { selectedSort = sort }
                    }
                } label: {
                    Label(selectedSort.rawValue, systemImage: "arrow.up.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)

            HStack {
                Text("\(resultCount) results").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !selectedChannels.isEmpty || selectedStatus != nil || !searchText.isEmpty {
                    Button("Reset filters") {
                        withAnimation(.snappy) {
                            selectedChannels.removeAll()
                            selectedStatus = nil
                            searchText = ""
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .premiumCard()
    }
}

private struct OrderDetailView: View {
    let order: Order
    let showToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ChannelIcon(channel: order.channel, size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(order.id).font(.title2.weight(.heavy))
                                Text(order.channel.rawValue).font(.subheadline).foregroundStyle(order.channel.tint)
                            }
                            Spacer()
                            StatusPill(state: order.state)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Order total").font(.caption).foregroundStyle(.secondary)
                                Text(order.total).font(.title.weight(.heavy))
                            }
                            Spacer()
                            Label(order.paid ? "Paid" : "Unpaid", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.green)
                        }
                    }
                    .premiumCard()

                    DetailGroup(title: "Customer") {
                        DetailLine(icon: "person.fill", title: order.customer, detail: order.email)
                        DetailLine(icon: "phone.fill", title: order.phone, detail: "Mobile")
                        DetailLine(icon: "mappin.and.ellipse", title: order.address, detail: "Shipping address")
                    }
                    DetailGroup(title: "Fulfillment") {
                        DetailLine(icon: "cube.box.fill", title: order.items, detail: "\(order.itemCount) item\(order.itemCount == 1 ? "" : "s")")
                        DetailLine(icon: "truck.box.fill", title: order.carrier, detail: order.tracking)
                        DetailLine(icon: "note.text", title: order.note, detail: "Order note")
                    }
                    VStack(spacing: 10) {
                        Button {
                            showToast("Shipping label added to print queue.")
                        } label: {
                            Label("Purchase & print label", systemImage: "printer.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PremiumButtonStyle())
                        HStack(spacing: 10) {
                            Button { showToast("Customer chat opened.") } label: {
                                Label("Message", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                            }
                            Button { showToast("Refund workflow opened.") } label: {
                                Label("Refund", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Order details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Chats

private struct InboxSummary: View {
    var body: some View {
        HStack(spacing: 8) {
            SummaryCell(value: "4", label: "Unread")
            SummaryCell(value: "2", label: "Priority")
            SummaryCell(value: "8m", label: "Reply time")
            SummaryCell(value: "96%", label: "Resolved")
        }
    }
}

private struct InboxCommandCenter: View {
    let showBulkComposer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unified inbox")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("4 channels • 96% resolved today")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Button(action: showBulkComposer) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Theme.blue)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            HStack(spacing: 8) {
                Label("2 priority", systemImage: "bolt.fill")
                Label("8m avg reply", systemImage: "timer")
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Theme.blue.opacity(0.16), radius: 22, y: 10)
    }
}

private struct FinancialPulseHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("68%").font(.caption2.weight(.semibold)).foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("Financial position").font(.headline.weight(.semibold)).foregroundStyle(.white)
                Text("$171,285 liquid + pending").font(.subheadline).foregroundStyle(.white.opacity(0.74))
                Text("+12.8% month over month").font(.caption).foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
        }
        .padding(18)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Theme.blue.opacity(0.2), radius: 24, y: 12)
    }
}

private struct SettingsControlHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Control center").font(.title3.weight(.semibold))
                    Text("Your account and operations are protected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.green)
                    .frame(width: 46, height: 46)
                    .background(Theme.mint, in: Circle())
            }
            HStack(spacing: 8) {
                ControlStatus(icon: "storefront.fill", value: "3", label: "Live stores")
                ControlStatus(icon: "person.2.fill", value: "4", label: "Team")
                ControlStatus(icon: "lock.fill", value: "2FA", label: "Secure")
            }
        }
        .premiumCard()
    }
}

private struct ControlStatus: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.blue)
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.softGray, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AssistantCapabilityStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            CapabilityCell(icon: "shippingbox.fill", label: "Orders", value: "Live")
            CapabilityCell(icon: "bubble.left.fill", label: "Inbox", value: "9")
            CapabilityCell(icon: "chart.line.uptrend.xyaxis", label: "Insights", value: "24/7")
        }
    }
}

private struct CapabilityCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon).font(.caption).foregroundStyle(Theme.blue)
                Spacer()
                Circle().fill(Theme.green).frame(width: 6, height: 6)
            }
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(conversation.priority ? Theme.softBlue : Theme.softGray)
                    .frame(width: 48, height: 48)
                    .overlay(Text(initials(conversation.customer)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.blue))
                ChannelIcon(channel: conversation.channel, size: 20)
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(conversation.customer).font(.subheadline.weight(.semibold))
                    if conversation.priority { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                    Spacer()
                    Text(conversation.time).font(.caption2).foregroundStyle(.secondary)
                }
                Text(conversation.preview).font(.subheadline).foregroundStyle(conversation.unread > 0 ? .primary : .secondary).lineLimit(1)
                HStack(spacing: 5) {
                    Text(conversation.orderID)
                    if conversation.priority {
                        Text("PRIORITY")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.orange.opacity(0.1), in: Capsule())
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if conversation.unread > 0 {
                Text("\(conversation.unread)").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20).background(Theme.blue, in: Circle())
            }
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(conversation.priority ? Theme.blue.opacity(0.12) : Theme.line, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.045), radius: 14, y: 7)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct ChatThreadView: View {
    let conversation: Conversation
    let showToast: (String) -> Void
    @State private var reply = ""
    @State private var messages: [ChatMessage]
    @State private var showingTemplates = false
    @Environment(\.dismiss) private var dismiss

    init(conversation: Conversation, showToast: @escaping (String) -> Void) {
        self.conversation = conversation
        self.showToast = showToast
        _messages = State(initialValue: conversation.messages)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    ChannelIcon(channel: conversation.channel, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.customer).font(.subheadline.weight(.bold))
                        Text("\(conversation.channel.shortName) • \(conversation.orderID)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showToast("Customer details opened.") } label: { Image(systemName: "person.crop.circle") }
                }
                .padding(14)
                .background(Theme.surface)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if !message.fromCustomer { Spacer(minLength: 55) }
                                VStack(alignment: message.fromCustomer ? .leading : .trailing, spacing: 4) {
                                    Text(message.text)
                                        .font(.subheadline)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 10)
                                        .background(message.fromCustomer ? Theme.softGray : Theme.ink)
                                        .foregroundStyle(message.fromCustomer ? Theme.ink : .white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(message.time).font(.caption2).foregroundStyle(.secondary)
                                }
                                if message.fromCustomer { Spacer(minLength: 55) }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(
                    Theme.canvas
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("AI suggests").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                        ForEach(aiSuggestions, id: \.self) { suggestion in
                            Button(suggestion) { reply = suggestion }
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .frame(height: 34)
                                .background(Theme.softBlue, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 7)
                    .background(Theme.surface)

                HStack(spacing: 10) {
                    Menu {
                        Button("Shipping update", systemImage: "truck.box") { reply = "Your order is moving through fulfillment now. I’ll send tracking as soon as the carrier scans it." }
                        Button("Delay apology", systemImage: "clock.badge.exclamationmark") { reply = "I’m sorry for the delay. I checked your order and I’m prioritizing the next available shipment update for you." }
                        Button("Return instructions", systemImage: "arrow.uturn.backward") { reply = "I can help with that return. Please confirm whether the item is unopened, and I’ll prepare the correct next step." }
                        Button("Manage presets", systemImage: "slider.horizontal.3") { showingTemplates = true }
                    } label: {
                        Image(systemName: "text.bubble.fill").frame(width: 34, height: 34)
                    }
                    TextField("Write a reply...", text: $reply, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.softGray, in: RoundedRectangle(cornerRadius: 8))
                    Button(action: sendReply) {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Theme.ink, in: Circle())
                    }
                    .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(reply.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .padding(12)
                .background(Theme.surface)
            }
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingTemplates) {
                MessagePresetView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var aiSuggestions: [String] {
        let context = messages.last(where: \.fromCustomer)?.text.lowercased() ?? conversation.preview.lowercased()
        if context.contains("friday") || context.contains("arrive") || context.contains("track") {
            return ["I’ll check the fastest delivery option.", "Your tracking update is being verified.", "I can upgrade shipping if available."]
        }
        if context.contains("apartment") || context.contains("address") {
            return ["Thanks, I updated the address details.", "I’ll retry the label with this unit number.", "Your shipment hold can now be cleared."]
        }
        return ["Thanks for reaching out. I’m checking this now.", "I found your order and can help.", "I’ll send you the next update shortly."]
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            messages.append(ChatMessage(text: text, time: "Now", fromCustomer: false))
            reply = ""
        }
    }
}

private struct MessagePresetView: View {
    @State private var presets = [
        "Your order is being prepared and tracking will follow shortly.",
        "I’m sorry for the delay. We are prioritizing your shipment.",
        "Thanks for confirming your address. The order hold is being cleared."
    ]
    @State private var newPreset = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Saved responses") {
                    ForEach(presets, id: \.self) { preset in Text(preset).font(.subheadline) }
                    .onDelete { presets.remove(atOffsets: $0) }
                }
                Section("Create preset") {
                    TextField("Response template", text: $newPreset, axis: .vertical)
                    Button("Add preset", systemImage: "plus") {
                        let clean = newPreset.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        presets.append(clean)
                        newPreset = ""
                    }
                }
            }
            .navigationTitle("Message presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct BulkMessageView: View {
    let showToast: (String) -> Void
    @State private var audience = "Unfulfilled buyers"
    @State private var message = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Audience") {
                    Picker("Recipients", selection: $audience) {
                        Text("Unfulfilled buyers").tag("Unfulfilled buyers")
                        Text("VIP customers").tag("VIP customers")
                        Text("TikTok Shop buyers").tag("TikTok Shop buyers")
                        Text("Delayed orders").tag("Delayed orders")
                    }
                    LabeledContent("Estimated recipients", value: "86 customers")
                }
                Section("Message") {
                    TextEditor(text: $message).frame(minHeight: 150)
                    Text("Marketplace messaging rules and opt-out preferences are applied automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        dismiss()
                        showToast("Bulk message scheduled for 86 customers.")
                    } label: {
                        Label("Review & schedule", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .disabled(message.isEmpty)
                }
            }
            .navigationTitle("Bulk message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Wallet

private struct WalletBalanceCard: View {
    let showToast: (String) -> Void
    let showDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Label balance").font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    AnimatedCurrencyText(value: 2_840.60, fontSize: 34, color: .white, fractionDigits: 2)
                }
                Spacer()
                Image(systemName: "wallet.bifold.fill").font(.title2).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Available for labels").font(.caption).foregroundStyle(.white.opacity(0.68))
                    Text("349 est. shipments").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                }
                Spacer()
                Button { showToast("Add funds opened.") } label: {
                    Label("Add funds", systemImage: "plus").font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Theme.ink)
            }
        }
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.16), radius: 22, y: 12)
        .onTapGesture(perform: showDetail)
    }
}

private struct FinancialMetricGrid: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            Button { showDetail(InsightDetail(title: "Pending payouts", subtitle: "Marketplace funds not yet deposited", value: "$42,345", rows: [("Shopify", "$18,420.18"), ("TikTok Shop", "$9,718.40"), ("Amazon", "$14,206.72"), ("Next arrival", "Jun 14"), ("On hold", "$0.00")], recommendations: ["All stores are within their expected payout windows.", "Shopify represents 43.5% of pending cash."])) } label: { FinanceMetric(title: "Pending payouts", value: "$42,345", detail: "Across 3 stores", tint: .blue) }.buttonStyle(PressableButtonStyle())
            Button { showDetail(InsightDetail(title: "Net profit", subtitle: "Profit after all tracked expenses", value: "$41,820", rows: [("Today", "$2,140"), ("Yesterday", "$1,890"), ("Last 7 days", "$10,420"), ("Last 30 days", "$41,820"), ("Margin", "32.4%")], recommendations: ["Margin is 2.8 points higher than last month.", "Reducing Amazon shipping delays protects $1,400 in projected margin."])) } label: { FinanceMetric(title: "Net profit", value: "$41,820", detail: "32.4% margin", tint: .green) }.buttonStyle(PressableButtonStyle())
            Button { showDetail(InsightDetail(title: "Advertising spend", subtitle: "Blended paid acquisition performance", value: "$21,680", rows: [("TikTok Ads", "$9,420 • 7.2x"), ("Meta Ads", "$7,810 • 5.8x"), ("Amazon Ads", "$4,450 • 4.1x"), ("Revenue attributed", "$128,996"), ("Blended ROAS", "5.95x")], recommendations: ["Shift 8% of Amazon budget to TikTok's top campaign.", "Pause three ad groups below 2.0x ROAS."])) } label: { FinanceMetric(title: "Ad spend", value: "$21,680", detail: "5.95x ROAS", tint: .pink) }.buttonStyle(PressableButtonStyle())
            Button { showDetail(InsightDetail(title: "Operating expenses", subtitle: "All costs captured this period", value: "$87,120", rows: [("Product costs", "$38,410"), ("Advertising", "$21,680"), ("Shipping", "$13,240"), ("Marketplace fees", "$13,790"), ("Percent of revenue", "67.6%")], recommendations: ["Product costs are within target.", "Shipping cost per order rose 6% this week."])) } label: { FinanceMetric(title: "Expenses", value: "$87,120", detail: "67.6% of revenue", tint: .orange) }.buttonStyle(PressableButtonStyle())
        }
    }
}

private struct ProfitChart: View {
    @Binding var selectedRange: String
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle(kicker: "Net cash flow", title: "$41,820")
                Spacer()
                MiniRangePicker(selection: $selectedRange)
            }
            ChartBars(
                values: [0.28, 0.45, 0.38, 0.58, 0.52, 0.72, 0.61, 0.86, 0.75, 0.92],
                labels: ["Jun 4", "Jun 5", "Jun 6", "Jun 7", "Jun 8", "Jun 9", "Jun 10", "Jun 11", "Jun 12", "Today"],
                amounts: ["$1,456", "$2,340", "$1,976", "$3,016", "$2,704", "$3,744", "$3,172", "$4,472", "$3,900", "$4,784"],
                tint: Theme.green
            )
        }
        .premiumCard()
    }
}

private struct PendingPayoutsCard: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(kicker: "Incoming", title: "Pending payouts")
            ForEach(DemoData.payouts) { payout in
                Button {
                    showDetail(InsightDetail(title: "\(payout.channel.rawValue) payout", subtitle: payout.date, value: payout.amount, rows: [("Status", payout.status), ("Orders included", payout.channel == .shopify ? "204" : payout.channel == .tiktok ? "148" : "91"), ("Gross sales", payout.channel == .shopify ? "$20,814" : "$16,220"), ("Fees withheld", payout.channel == .amazon ? "-$2,013" : "-$1,145"), ("Reserve", "$0.00")], recommendations: ["No action is required for this payout."]))
                } label: {
                    HStack(spacing: 12) {
                    ChannelIcon(channel: payout.channel, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(payout.channel.rawValue).font(.subheadline.weight(.bold))
                        Text(payout.date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(payout.amount).font(.subheadline.weight(.heavy))
                        Text(payout.status).font(.caption2).foregroundStyle(.blue)
                    }
                }
                }
                .buttonStyle(.plain)
                if payout.id != DemoData.payouts.last?.id { Divider() }
            }
        }
        .premiumCard()
    }
}

private struct ExpenseBreakdownCard: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(kicker: "This month", title: "Expense breakdown")
            ForEach(DemoData.expenses) { expense in
                Button {
                    showDetail(InsightDetail(title: expense.title, subtitle: expense.detail, value: expense.value, rows: [("Today", "$1,284"), ("Yesterday", "$1,190"), ("Last 7 days", "$8,822"), ("Last 30 days", expense.value), ("Change", "+4.2%")], recommendations: ["Tap export to review the underlying transactions.", "This category is currently within its target range."]))
                } label: {
                    HStack(spacing: 12) {
                    Image(systemName: expense.systemImage).foregroundStyle(expense.tint)
                        .frame(width: 38, height: 38).background(expense.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(expense.title).font(.subheadline.weight(.bold))
                        Text(expense.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(expense.value).font(.subheadline.weight(.heavy))
                }
                }
                .buttonStyle(.plain)
            }
        }
        .premiumCard()
    }
}

private struct ROICard: View {
    let showDetail: (InsightDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(kicker: "Advertising", title: "Return on ad spend")
            HStack(spacing: 10) {
                Button { showDetail(roiDetail("TikTok", "7.2x", "$9,420")) } label: { ROIChannel(name: "TikTok", value: "7.2x", change: "+18%", tint: .pink) }.buttonStyle(.plain)
                Button { showDetail(roiDetail("Meta", "5.8x", "$7,810")) } label: { ROIChannel(name: "Meta", value: "5.8x", change: "+9%", tint: .blue) }.buttonStyle(.plain)
                Button { showDetail(roiDetail("Amazon", "4.1x", "$4,450")) } label: { ROIChannel(name: "Amazon", value: "4.1x", change: "-3%", tint: .orange) }.buttonStyle(.plain)
            }
        }
        .premiumCard()
    }

    private func roiDetail(_ name: String, _ roas: String, _ spend: String) -> InsightDetail {
        InsightDetail(title: "\(name) advertising", subtitle: "Campaign-level return on ad spend", value: roas, rows: [("Spend", spend), ("Attributed revenue", name == "TikTok" ? "$67,824" : "$45,298"), ("Purchases", name == "TikTok" ? "612" : "388"), ("Cost per purchase", name == "TikTok" ? "$15.39" : "$20.13"), ("Trend", name == "Amazon" ? "-3%" : "+18%")], recommendations: name == "Amazon" ? ["Pause low-converting broad-match keywords.", "Move budget to branded and top-SKU campaigns."] : ["Increase the best campaign budget gradually by 10%."])
    }
}

// MARK: - Settings

private struct ProfileCard: View {
    @EnvironmentObject private var workspace: UserWorkspace
    let edit: () -> Void

    var body: some View {
        let displayName = workspace.isRealAccount ? workspace.profile.name : "Rich G."
        let company = workspace.isRealAccount ? workspace.profile.company : "Northstar Goods LLC"
        let email = workspace.isRealAccount ? workspace.profile.email : "goengiplays@gmail.com"
        HStack(spacing: 14) {
            Circle().fill(Theme.softBlue).frame(width: 58, height: 58)
                .overlay(Text(initials(displayName)).font(.headline.weight(.heavy)).foregroundStyle(.blue))
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.isEmpty ? "Account owner" : displayName).font(.headline.weight(.semibold))
                Text(company.isEmpty ? "Owner" : "Owner • \(company)").font(.subheadline).foregroundStyle(.secondary)
                Text(email).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: edit) { Image(systemName: "pencil") }
                .buttonStyle(.bordered)
        }
        .premiumCard()
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private struct StoresCard: View {
    @EnvironmentObject private var workspace: UserWorkspace
    @Binding var showingAddStore: Bool
    let showToast: (String) -> Void
    @State private var connections = DemoData.connections

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(kicker: "Connections", title: "Stores")
                Spacer()
                Button { showingAddStore = true } label: { Label("Add", systemImage: "plus") }
                    .font(.subheadline.weight(.bold))
            }
            if workspace.isRealAccount && workspace.connectedStores.isEmpty {
                Text("No stores connected yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(workspace.connectedStores, id: \.self) { store in
                HStack {
                    Image(systemName: "storefront.fill")
                        .foregroundStyle(Theme.green)
                        .frame(width: 38, height: 38)
                        .background(Theme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    Text(store).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Live").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                }
            }
            ForEach(workspace.isRealAccount ? [] : connections) { connection in
                HStack(spacing: 12) {
                    ChannelIcon(channel: connection.channel, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(connection.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(connection.status).font(.caption.weight(.semibold))
                        .foregroundStyle(connection.status == "Live" ? Theme.green : .orange)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background((connection.status == "Live" ? Theme.green : Color.orange).opacity(0.1), in: Capsule())
                    Menu {
                        if connection.isConnected {
                            Button("Connection details", systemImage: "info.circle") {
                                showToast("\(connection.name) connection details opened.")
                            }
                            Button("Sync now", systemImage: "arrow.clockwise") {
                                showToast("\(connection.name) is syncing.")
                            }
                            Button("Disconnect store", systemImage: "link.badge.minus", role: .destructive) {
                                withAnimation(.snappy) {
                                    connections.removeAll { $0.id == connection.id }
                                }
                                showToast("\(connection.name) disconnected.")
                            }
                        } else {
                            Button("Connect store", systemImage: "link.badge.plus") {
                                showingAddStore = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(Theme.softGray, in: Circle())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if connection.isConnected {
                        showToast("\(connection.name) connection details opened.")
                    } else {
                        showingAddStore = true
                    }
                }
            }
        }
        .premiumCard()
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .premiumCard()
    }
}

private struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 34, height: 34).background(Theme.softBlue, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.ink)
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 34, height: 34).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AddStoreView: View {
    @EnvironmentObject private var workspace: UserWorkspace
    let showToast: (String) -> Void
    @State private var selectedChannel: SalesChannel?
    @State private var shopDomain = ""
    @State private var storeNickname = ""
    @State private var showingConnectionForm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect another sales channel to import orders, messages, payouts, and fulfillment data.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 4)
                    ForEach([SalesChannel.shopify, .tiktok, .amazon, .walmart]) { channel in
                        Button {
                            selectedChannel = channel
                            showingConnectionForm = true
                        } label: {
                            HStack(spacing: 13) {
                                ChannelIcon(channel: channel, size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(channel.rawValue).font(.headline.weight(.bold)).foregroundStyle(.primary)
                                    Text(storeDescription(channel)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                            }
                            .premiumCard()
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Add a store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingConnectionForm) {
                NavigationStack {
                    Form {
                        Section("Store") {
                            TextField("Store nickname", text: $storeNickname)
                            if selectedChannel == .shopify {
                                TextField("your-store.myshopify.com", text: $shopDomain)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                            } else {
                                LabeledContent("Marketplace", value: selectedChannel?.rawValue ?? "")
                            }
                        }
                        Section {
                            Label("Ship Demon requests only the order, customer, fulfillment, messaging, and payout scopes needed for this app.", systemImage: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section {
                            Button {
                                if selectedChannel == .shopify {
                                    Task {
                                        do {
                                            let url = try await ShopifyIntegration.shared.installationURL(for: normalizedShopDomain)
                                            await UIApplication.shared.open(url)
                                        } catch {
                                            showToast(error.localizedDescription)
                                        }
                                    }
                                } else {
                                    let channel = selectedChannel?.rawValue ?? "Store"
                                    workspace.addStore("\(channel):\(storeNickname.isEmpty ? channel : storeNickname)")
                                    showingConnectionForm = false
                                    dismiss()
                                    showToast("\(channel) OAuth handoff prepared.")
                                }
                            } label: {
                                Label("Continue securely", systemImage: "arrow.up.forward.app")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .disabled(selectedChannel == .shopify && normalizedShopDomain.isEmpty)
                        } footer: {
                            Text("Shopify connects through the secure Ship Demon backend. Client credentials and access tokens never live inside this iPhone app.")
                        }
                    }
                    .navigationTitle(selectedChannel == .shopify ? "Connect Shopify" : "Connect \(selectedChannel?.shortName ?? "store")")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { showingConnectionForm = false } } }
                }
            }
        }
    }

    private var normalizedShopDomain: String {
        shopDomain
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func storeDescription(_ channel: SalesChannel) -> String {
        switch channel {
        case .shopify: return "Connect any Shopify storefront"
        case .tiktok: return "Connect TikTok Shop Seller Center"
        case .amazon: return "Connect Amazon Seller Central"
        case .walmart: return "Connect Walmart Marketplace"
        case .all: return ""
        }
    }
}

private struct EditProfileView: View {
    @EnvironmentObject private var workspace: UserWorkspace
    let showToast: (String) -> Void
    @State private var name = "Rich G."
    @State private var email = "goengiplays@gmail.com"
    @State private var company = "Northstar Goods LLC"
    @State private var phone = "(646) 555-0199"
    @State private var timezone = "America/New_York"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal information") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Business") {
                    TextField("Company", text: $company)
                    Picker("Timezone", selection: $timezone) {
                        Text("Eastern Time").tag("America/New_York")
                        Text("Central Time").tag("America/Chicago")
                        Text("Mountain Time").tag("America/Denver")
                        Text("Pacific Time").tag("America/Los_Angeles")
                    }
                }
                Section {
                    Button {
                        if workspace.isRealAccount {
                            workspace.saveProfile(WorkspaceProfile(name: name, email: email, phone: phone, company: company))
                        }
                        dismiss()
                        showToast("Profile information saved.")
                    } label: {
                        Label("Save changes", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
            .task {
                guard workspace.isRealAccount else { return }
                name = workspace.profile.name
                email = workspace.profile.email
                phone = workspace.profile.phone
                company = workspace.profile.company
            }
        }
    }
}

private struct CompanyDetailsView: View {
    let showToast: (String) -> Void
    @State private var legalName = "Northstar Goods LLC"
    @State private var displayName = "Northstar Goods"
    @State private var supportEmail = "support@northstargoods.com"
    @State private var supportPhone = "(646) 555-0199"
    @State private var website = "northstargoods.com"
    @State private var taxID = "••-•••4821"
    @State private var address = "88 Kent Ave"
    @State private var city = "Brooklyn"
    @State private var state = "NY"
    @State private var postalCode = "11249"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 13) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName).font(.title3.weight(.heavy))
                            Text("Company identity and customer-facing details")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .premiumCard()

                    CompanyFieldGroup(title: "Business identity") {
                        TextField("Legal company name", text: $legalName)
                        Divider()
                        TextField("Display name", text: $displayName)
                        Divider()
                        TextField("Tax ID", text: $taxID)
                    }

                    CompanyFieldGroup(title: "Customer contact") {
                        TextField("Support email", text: $supportEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Divider()
                        TextField("Support phone", text: $supportPhone)
                            .keyboardType(.phonePad)
                        Divider()
                        TextField("Website", text: $website)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    }

                    CompanyFieldGroup(title: "Business address") {
                        TextField("Street address", text: $address)
                        Divider()
                        TextField("City", text: $city)
                        Divider()
                        HStack {
                            TextField("State", text: $state)
                            Divider()
                            TextField("Postal code", text: $postalCode)
                                .keyboardType(.numbersAndPunctuation)
                        }
                    }

                    Button {
                        dismiss()
                        showToast("Company details saved.")
                    } label: {
                        Label("Save company details", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Company details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct CompanyFieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content
                .font(.subheadline)
                .padding(.vertical, 3)
        }
        .premiumCard()
    }
}

private struct InsightDetailView: View {
    let detail: InsightDetail
    let showToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("LIVE INSIGHT")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Image(systemName: "sparkles")
                                .foregroundStyle(.white)
                                .symbolEffect(.pulse)
                        }
                        Text(detail.value)
                            .font(.system(size: 42, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(detail.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.74))
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach([0.28, 0.42, 0.36, 0.58, 0.49, 0.72, 0.64, 0.88, 0.76, 0.96], id: \.self) { value in
                                Capsule()
                                    .fill(.white.opacity(0.24 + value * 0.55))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 8 + value * 34)
                            }
                        }
                        .frame(height: 45, alignment: .bottom)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Theme.blue.opacity(0.24), radius: 24, y: 12)

                    VStack(spacing: 0) {
                        ForEach(Array(detail.rows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Circle()
                                    .fill(index == 0 ? Theme.blue : Theme.softBlue)
                                    .frame(width: 7, height: 7)
                                Text(row.0).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.1).font(.subheadline.weight(.bold)).multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 12)
                            if index != detail.rows.count - 1 { Divider() }
                        }
                    }
                    .premiumCard()

                    if !detail.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(kicker: "Ship Demon insights", title: "What to do next")
                            ForEach(Array(detail.recommendations.enumerated()), id: \.offset) { index, recommendation in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: index == 0 ? "bolt.fill" : "arrow.up.right")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(index == 0 ? Theme.blue : Theme.ink, in: Circle())
                                    Text(recommendation).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .premiumCard()
                    }

                    HStack(spacing: 10) {
                        Button {
                            showToast("\(detail.title) report exported.")
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            showToast("Action workflow opened.")
                        } label: {
                            Label("Take action", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct OrderAnalyticsView: View {
    @State private var period = "Today"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(["Today", "Yesterday", "7 Days", "30 Days"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        SummaryCell(value: "20", label: "Amazon")
                        SummaryCell(value: "30", label: "TikTok")
                        SummaryCell(value: "24", label: "Shopify")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(kicker: "Order velocity", title: "Today vs yesterday")
                        HStack(alignment: .bottom, spacing: 18) {
                            ComparisonBar(label: "Yesterday", value: 0.68, orders: "61")
                            ComparisonBar(label: "Today", value: 0.86, orders: "74")
                        }
                        HStack {
                            Label("+21.3%", systemImage: "arrow.up.right").foregroundStyle(Theme.green)
                            Text("13 more orders than yesterday").foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .premiumCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(kicker: "Products", title: "Most ordered")
                        ProductRank(rank: 1, name: "Hydration Starter Kit", orders: "48 orders", revenue: "$3,456")
                        ProductRank(rank: 2, name: "Skin Reset Bundle", orders: "39 orders", revenue: "$5,421")
                        ProductRank(rank: 3, name: "Linen Overshirt", orders: "31 orders", revenue: "$3,658")
                        ProductRank(rank: 4, name: "Travel Organizer", orders: "24 orders", revenue: "$1,411")
                    }
                    .premiumCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(kicker: "Fulfillment health", title: "What is helping or hurting")
                        HealthSignal(title: "Same-day fulfillment", value: "91%", change: "+4.2%", tint: Theme.green)
                        HealthSignal(title: "Late shipments", value: "4", change: "-2", tint: .orange)
                        HealthSignal(title: "Refund requests", value: "7", change: "+1", tint: .pink)
                        HealthSignal(title: "Average order value", value: "$92.40", change: "+8.1%", tint: .blue)
                    }
                    .premiumCard()
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Order analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ShipmentTrackerView: View {
    @State private var selectedSegment = "Shipments"
    @State private var selectedOrder: Order?
    @State private var toast: String?
    @State private var selectedManifest: DemoManifest?
    @Environment(\.dismiss) private var dismiss

    private let manifests = [
        DemoManifest(id: "MF-0613-USPS", service: "USPS Ground Advantage", orderCount: 38, status: "Closed 10:42 AM", totalWeight: "186.4 lb"),
        DemoManifest(id: "MF-0613-UPS", service: "UPS Ground", orderCount: 27, status: "Ready to close", totalWeight: "244.8 lb"),
        DemoManifest(id: "MF-0613-PRIORITY", service: "USPS Priority", orderCount: 14, status: "Printing labels", totalWeight: "72.1 lb")
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shipment control")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Track every package and close carrier manifests")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                Spacer()
                                Image(systemName: "location.fill.viewfinder")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.white.opacity(0.14), in: Circle())
                            }
                            HStack(spacing: 8) {
                                TrackerSummary(value: "86", label: "In transit")
                                TrackerSummary(value: "12", label: "Out today")
                                TrackerSummary(value: "4", label: "Exceptions")
                            }
                        }
                        .padding(18)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Theme.blue.opacity(0.22), radius: 24, y: 12)

                        Picker("Tracker mode", selection: $selectedSegment) {
                            Text("Shipments").tag("Shipments")
                            Text("Manifests").tag("Manifests")
                        }
                        .pickerStyle(.segmented)

                        if selectedSegment == "Shipments" {
                            VStack(spacing: 10) {
                                ForEach(DemoData.orders.prefix(12)) { order in
                                    Button { selectedOrder = order } label: {
                                        ShipmentRow(order: order)
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(manifests.enumerated()), id: \.element.id) { index, manifest in
                                    Button {
                                        selectedManifest = manifest
                                    } label: {
                                        VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: index == 0 ? "checkmark.seal.fill" : "doc.text.fill")
                                                .foregroundStyle(index == 0 ? Theme.green : Theme.blue)
                                                .frame(width: 38, height: 38)
                                                .background((index == 0 ? Theme.mint : Theme.softBlue), in: RoundedRectangle(cornerRadius: 10))
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(manifest.id).font(.subheadline.weight(.semibold))
                                                Text(manifest.service).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Menu {
                                                Button("View manifest", systemImage: "doc.text.magnifyingglass") {
                                                    selectedManifest = manifest
                                                }
                                                Button("Print manifest", systemImage: "printer") {
                                                    showToast("\(manifest.id) sent to printer.")
                                                }
                                                Button("Export PDF", systemImage: "square.and.arrow.up") {
                                                    showToast("\(manifest.id) PDF prepared.")
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis.circle")
                                            }
                                        }
                                        HStack {
                                            Text("\(manifest.orderCount) orders").font(.caption.weight(.medium))
                                            Spacer()
                                            Text(manifest.status).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .premiumCard()
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Theme.canvas)

                if let toast {
                    TopToastBanner(text: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .navigationTitle("Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selectedOrder) { order in
                OrderDetailView(order: order, showToast: showToast)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedManifest) { manifest in
                ManifestDetailView(manifest: manifest, showToast: showToast)
                    .presentationDetents([.large])
            }
        }
    }

    private func showToast(_ text: String) {
        ToastCenter.show(text, toast: $toast)
    }
}

private struct DemoManifest: Identifiable {
    let id: String
    let service: String
    let orderCount: Int
    let status: String
    let totalWeight: String
}

private struct PrintCenterView: View {
    @State private var selectedMode = "Queue"
    @Environment(\.dismiss) private var dismiss

    private var orders: [Order] {
        selectedMode == "Queue"
            ? Array(DemoData.orders.filter { $0.state == .ready }.prefix(12))
            : Array(DemoData.orders.filter { $0.state == .shipped || $0.state == .delivered }.prefix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Print status", selection: $selectedMode) {
                        Text("Queue").tag("Queue")
                        Text("Printed").tag("Printed")
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        SummaryCell(value: selectedMode == "Queue" ? "86" : "214", label: selectedMode == "Queue" ? "Queued" : "Printed")
                        SummaryCell(value: selectedMode == "Queue" ? "$712" : "$1,846", label: "Label value")
                        SummaryCell(value: "3", label: "Carriers")
                    }

                    ForEach(orders) { order in
                        HStack(spacing: 11) {
                            Image(order.productImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(order.items).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(order.id) • \(order.carrier)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedMode == "Queue" ? "clock.fill" : "checkmark.circle.fill")
                                .foregroundStyle(selectedMode == "Queue" ? Theme.blue : Color.green)
                        }
                        .premiumCard()
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Print center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Print all", systemImage: "printer.fill") { }
                        .disabled(selectedMode != "Queue")
                }
            }
        }
    }
}

private struct ManifestDetailView: View {
    let manifest: DemoManifest
    let showToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CARRIER MANIFEST").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                        Text(manifest.id).font(.title2.weight(.semibold)).foregroundStyle(.white)
                        Text(manifest.service).font(.subheadline).foregroundStyle(.white.opacity(0.76))
                        HStack(spacing: 8) {
                            TrackerSummary(value: "\(manifest.orderCount)", label: "Packages")
                            TrackerSummary(value: manifest.totalWeight, label: "Weight")
                            TrackerSummary(value: "1", label: "Pickup")
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))

                    VStack(spacing: 0) {
                        manifestRow("Status", manifest.status)
                        Divider()
                        manifestRow("Created", "June 14, 2026 • 10:18 AM")
                        Divider()
                        manifestRow("Pickup", "Today • 4:30 PM")
                        Divider()
                        manifestRow("Origin", "Northstar Fulfillment • Brooklyn, NY")
                        Divider()
                        manifestRow("SCAC", manifest.service.contains("UPS") ? "UPSN" : "USPS")
                    }
                    .premiumCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(kicker: "Included", title: "Sample shipments")
                        ForEach(Array(DemoData.orders.prefix(5))) { order in
                            CompactOrderRow(order: order)
                            if order.id != DemoData.orders.prefix(5).last?.id { Divider() }
                        }
                    }
                    .premiumCard()
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Manifest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Print manifest", systemImage: "printer") { showToast("\(manifest.id) sent to printer.") }
                        Button("Export PDF", systemImage: "square.and.arrow.up") { showToast("\(manifest.id) PDF prepared.") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func manifestRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 11)
    }
}

private struct TrackerSummary: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.weight(.semibold)).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShipmentRow: View {
    let order: Order

    private var progress: CGFloat {
        switch order.state {
        case .ready, .hold, .message: return 0.18
        case .processing: return 0.38
        case .shipped: return 0.68
        case .delivered: return 1
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(order.productImage)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(order.id).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(order.state.rawValue).font(.caption).foregroundStyle(order.state.tint)
                }
                Text("\(order.carrier) • \(order.customer)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GeometryReader { geometry in
                    Capsule().fill(Theme.softGray)
                        .overlay(alignment: .leading) {
                            Capsule().fill(order.state.tint).frame(width: geometry.size.width * progress)
                        }
                }
                .frame(height: 5)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .premiumCard()
    }
}

private struct ComparisonBar: View {
    let label: String
    let value: CGFloat
    let orders: String

    var body: some View {
        VStack(spacing: 8) {
            Text(orders).font(.headline.weight(.heavy))
            RoundedRectangle(cornerRadius: 6)
                .fill(label == "Today" ? Theme.ink : Theme.softBlue)
                .frame(height: value * 130)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProductRank: View {
    let rank: Int
    let name: String
    let orders: String
    let revenue: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.caption.weight(.heavy)).foregroundStyle(.blue)
                .frame(width: 28, height: 28).background(Theme.softBlue, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.bold))
                Text(orders).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(revenue).font(.subheadline.weight(.heavy))
        }
    }
}

private struct HealthSignal: View {
    let title: String
    let value: String
    let change: String
    let tint: Color

    var body: some View {
        HStack {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.subheadline.weight(.heavy))
            Text(change).font(.caption.weight(.bold)).foregroundStyle(tint)
        }
    }
}

// MARK: - Shared UI

private enum Theme {
    static let ink = Color(uiColor: .label)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.03, blue: 0.045, alpha: 1)
            : UIColor(red: 0.992, green: 0.978, blue: 0.988, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)
    static let line = Color(uiColor: .separator).opacity(0.35)
    static let softGray = Color(uiColor: .tertiarySystemFill)
    static let softBlue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.08, blue: 0.20, alpha: 1)
            : UIColor(red: 0.985, green: 0.89, blue: 0.95, alpha: 1)
    })
    static let mint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.07, blue: 0.10, alpha: 1)
            : UIColor(red: 1.0, green: 0.89, blue: 0.92, alpha: 1)
    })
    static let green = Color(red: 0.88, green: 0.08, blue: 0.24)
    static let blue = Color(red: 0.58, green: 0.12, blue: 0.78)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.96, green: 0.04, blue: 0.18), Color(red: 0.63, green: 0.08, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct Screen<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    let toast: String?
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing
    @State private var showingOperationsPulse = false
    @StateObject private var assistant = AssistantManager.shared
    @EnvironmentObject private var workspace: UserWorkspace

    private var visibleUnreadCount: Int {
        workspace.isRealAccount && !workspace.hasStores ? 0 : assistant.unreadCount
    }

    init(
        title: String,
        subtitle: String,
        toast: String?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.toast = toast
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title).font(.system(size: 31, weight: .semibold))
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 125)
                }
                .background(Theme.canvas)
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await assistant.refreshAlerts()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { _ in
                            NotificationCenter.default.post(name: .shipDemonScrollActivity, object: nil)
                        }
                )

                if let toast {
                    TopToastBanner(text: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingOperationsPulse = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.and.waves.left.and.right")
                            if visibleUnreadCount > 0 {
                                Text("\(visibleUnreadCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(.red, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                    .offset(x: 7, y: -7)
                            }
                        }
                    }
                    .accessibilityLabel("Open operations assistant alerts")
                }
                ToolbarItem(placement: .principal) {
                    Text("Ship Demon").font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) { trailing }
            }
            .sheet(isPresented: $showingOperationsPulse) {
                OperationsPulseView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct BottomDock: View {
    @Binding var selection: AppTab
    let onInteraction: () -> Void
    @Namespace private var selectionMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    onInteraction()
                    withAnimation(.snappy(duration: 0.24)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selection == tab {
                                Circle()
                                    .fill(tab == .assistant ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.white.opacity(0.78)))
                                    .frame(width: tab == .assistant ? 44 : 38, height: tab == .assistant ? 44 : 38)
                                    .matchedGeometryEffect(id: "dock-selection", in: selectionMotion)
                                    .shadow(color: Theme.blue.opacity(tab == .assistant ? 0.28 : 0.13), radius: 12, y: 5)
                            } else if tab == .assistant {
                                Circle()
                                    .fill(Theme.brandGradient)
                                    .frame(width: 42, height: 42)
                                    .shadow(color: Theme.blue.opacity(0.24), radius: 12, y: 5)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(tab == .assistant ? .white : (selection == tab ? Theme.blue : .secondary))
                            if tab == .assistant {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                    .shadow(color: .green.opacity(0.8), radius: 5)
                                    .offset(x: 15, y: -15)
                                    .phaseAnimator([false, true]) { content, active in
                                        content
                                            .scaleEffect(active ? 1.28 : 0.82)
                                            .opacity(active ? 1 : 0.55)
                                    } animation: { _ in
                                        .easeInOut(duration: 0.8)
                                    }
                            }
                        }
                        .frame(height: 44)
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(tab == .assistant ? Theme.blue : (selection == tab ? Theme.ink : .secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.38), Theme.blue.opacity(0.06), .white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.88), lineWidth: 1))
        .shadow(color: Theme.blue.opacity(0.10), radius: 28, y: 12)
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { gesture in
                    onInteraction()
                    guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.4 else { return }
                    let tabs = AppTab.allCases
                    guard let index = tabs.firstIndex(of: selection) else { return }
                    let next = gesture.translation.width < 0
                        ? min(index + 1, tabs.count - 1)
                        : max(index - 1, 0)
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        selection = tabs[next]
                    }
                }
        )
    }
}

private struct AssistantView: View {
    @StateObject private var assistant = AssistantManager.shared
    @State private var input = ""
    @State private var showingVoiceSettings = false
    @State private var showingFileImporter = false
    @State private var attachments: [AssistantAttachment] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        AssistantStatusCard(name: assistant.name)
                        AssistantCapabilityStrip()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                AssistantPrompt(title: "Winning item", icon: "trophy.fill") {
                                    assistant.send("What is my winning item?")
                                }
                                AssistantPrompt(title: "Weakest item", icon: "arrow.down.right") {
                                    assistant.send("What is my worst performing item?")
                                }
                                AssistantPrompt(title: "Orders this week", icon: "shippingbox.fill") {
                                    assistant.send("How many new orders this week?")
                                }
                            }
                        }
                        ForEach(assistant.messages) { message in
                            AssistantBubble(message: message) { }
                        }
                        if assistant.isThinking {
                            HStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle().fill(Theme.green).frame(width: 7, height: 7)
                                        .phaseAnimator([false, true]) { content, active in
                                            content.offset(y: active ? -4 : 2)
                                        } animation: { _ in
                                            .easeInOut(duration: 0.42).delay(Double(index) * 0.1)
                                        }
                                }
                                Text("\(assistant.name) is analyzing your stores")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(16)
                }
                .background(Theme.canvas)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { _ in
                            NotificationCenter.default.post(name: .shipDemonScrollActivity, object: nil)
                        }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                assistantComposer
            }
            .navigationTitle(assistant.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingVoiceSettings) {
                VoiceSettingsView()
                    .presentationDetents([.medium])
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image, .pdf, .plainText, .commaSeparatedText, .json, .data],
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result else { return }
                attachments.append(contentsOf: urls.prefix(5).compactMap(assistant.attachment(from:)))
            }
        }
    }

    private var assistantComposer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 7) {
                                Image(systemName: attachment.kind.icon)
                                Text(attachment.name).lineLimit(1)
                                Button {
                                    attachments.removeAll { $0.id == attachment.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.8)))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(spacing: 9) {
                Button { showingFileImporter = true } label: {
                    Image(systemName: "paperclip")
                        .font(.title3).foregroundStyle(Theme.blue)
                }
                Button { showingVoiceSettings = true } label: {
                    Image(systemName: assistant.voiceRepliesEnabled ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title2).foregroundStyle(Theme.blue)
                }
                TextField("Message \(assistant.name)...", text: $input, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                Button {
                    assistant.send(input, attachments: attachments)
                    input = ""
                    attachments = []
                } label: {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.brandGradient, in: Circle())
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .padding(.bottom, 76)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

private struct VoiceSettingsView: View {
    @StateObject private var assistant = AssistantManager.shared
    private let voices = ["Samantha", "Ava", "Alex", "Daniel"]

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Voice responses", isOn: $assistant.voiceRepliesEnabled)
                Picker("Voice", selection: $assistant.selectedVoiceName) {
                    ForEach(voices, id: \.self) { Text($0).tag($0) }
                }
                Button("Preview voice", systemImage: "speaker.wave.2.fill") {
                    assistant.speak("Hi, I’m \(assistant.name). I’m ready to help manage your stores.")
                }
            }
            .navigationTitle("Assistant voice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct OperationsPulseView: View {
    @StateObject private var assistant = AssistantManager.shared
    @EnvironmentObject private var workspace: UserWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var expandedAlertID: String?

    private var visibleAlerts: [AssistantAlert] {
        workspace.isRealAccount && !workspace.hasStores ? [] : assistant.alerts
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Operations pulse").font(.system(size: 30, weight: .heavy))
                        Text("\(assistant.name) is monitoring fulfillment, inventory, messages, returns, payouts, and ads.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if visibleAlerts.isEmpty {
                        ContentUnavailableView("You are all caught up", systemImage: "checkmark.circle.fill", description: Text("New operational updates will appear here."))
                            .padding(.top, 48)
                    }

                    ForEach(visibleAlerts) { alert in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(alignment: .top) {
                                Circle()
                                    .fill(alert.isRead ? Theme.line : alert.severity.color)
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alert.title).font(.headline.weight(alert.isRead ? .medium : .semibold))
                                    Text(alert.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    withAnimation(.snappy) { assistant.clear(alert.id) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.softGray, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            if expandedAlertID == alert.id {
                                HStack(spacing: 8) {
                                    Label(alert.isRead ? "Read" : "New", systemImage: alert.isRead ? "checkmark.circle" : "sparkles")
                                    Text("Updated just now")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            HStack {
                                Button(expandedAlertID == alert.id ? "Show less" : "View more") {
                                    assistant.markRead(alert.id)
                                    withAnimation(.snappy) {
                                        expandedAlertID = expandedAlertID == alert.id ? nil : alert.id
                                    }
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    assistant.execute(alert)
                                    dismiss()
                                } label: {
                                    Label(alert.action, systemImage: "arrow.up.right")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(alert.severity.color)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            assistant.markRead(alert.id)
                            withAnimation(.snappy) {
                                expandedAlertID = expandedAlertID == alert.id ? nil : alert.id
                            }
                        }
                        .premiumCard()
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Assistant alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !assistant.alerts.isEmpty {
                        Button("Clear all", role: .destructive) { assistant.clearAll() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct AssistantStatusCard: View {
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.white.opacity(0.17))
                Circle().stroke(.white.opacity(0.28), lineWidth: 1).padding(5)
                Image(systemName: "sparkles").font(.title2.weight(.medium)).foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(name) is online").font(.headline.weight(.semibold)).foregroundStyle(.white)
                Text("Monitoring 4 stores and 56 active records").font(.caption).foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
            Circle().fill(.green).frame(width: 9, height: 9)
        }
        .padding(18)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Theme.blue.opacity(0.22), radius: 24, y: 12)
    }
}

private struct AssistantPrompt: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage
    let action: () -> Void

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 42) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 9) {
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        AssistantAttachmentPreview(attachment: attachment)
                    }
                }
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? .white : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(message.isUser ? Theme.blue : .white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if !message.isUser {
                            RoundedRectangle(cornerRadius: 16).stroke(Theme.line)
                        }
                    }
                if let visual = message.visual {
                    AssistantVisualCard(visual: visual)
                }
                if let label = message.actionLabel {
                    Button(label, action: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            if !message.isUser { Spacer(minLength: 42) }
        }
    }
}

private struct AssistantAttachmentPreview: View {
    let attachment: AssistantAttachment

    var body: some View {
        Group {
            if attachment.kind == .image,
               let data = attachment.data,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 190, height: 130)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(attachment.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Label(attachment.name, systemImage: attachment.kind.icon)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.8)))
            }
        }
    }
}

private struct AssistantVisualCard: View {
    let visual: AssistantVisual

    var body: some View {
        switch visual {
        case let .product(image, name, subtitle, metrics, insights, tint):
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(tint).frame(width: 9, height: 9)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.0).font(.caption2).foregroundStyle(.secondary)
                            Text(metric.1).font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.elevatedSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                ForEach(insights, id: \.self) { insight in
                    Label(insight, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .assistantGlassCard(tint: tint)

        case let .overview(title, value, change, metrics, tint):
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Text(value).font(.system(size: 31, weight: .semibold))
                    }
                    Spacer()
                    Text(change)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                }
                HStack(spacing: 7) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.0).font(.caption2).foregroundStyle(.secondary)
                            Text(metric.1).font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .assistantGlassCard(tint: tint)
        }
    }
}

private extension View {
    func assistantGlassCard(tint: Color) -> some View {
        self
            .padding(15)
            .frame(maxWidth: 310, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.9)))
            .shadow(color: tint.opacity(0.12), radius: 20, y: 9)
    }
}

private extension View {
    func premiumCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Theme.blue.opacity(0.04), radius: 8, x: -3, y: 2)
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct SectionTitle: View {
    let kicker: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(title).font(.headline.weight(.heavy))
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 13).frame(height: 44)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }
}

private struct FilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.bold))
                .foregroundStyle(selected ? .white : Theme.ink)
                .padding(.horizontal, 12).frame(height: 34)
                .background(selected ? Theme.ink : .white, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct MiniRangePicker: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(["7D", "30D", "90D"], id: \.self) { range in
                Button(range) { withAnimation(.snappy) { selection = range } }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).frame(height: 32)
            .background(Theme.softGray, in: Capsule())
        }
    }
}

private struct ChartBars: View {
    let values: [CGFloat]
    let labels: [String]
    let amounts: [String]
    let tint: Color
    @State private var selectedIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let selected = selectedIndex == index
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? tint : tint.opacity(0.16 + Double(index) * 0.045))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(24, value * 128))
                                .shadow(color: selected ? tint.opacity(0.3) : .clear, radius: 10, y: 4)
                        }
                        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selectedIndex)
                    }
                }
                .frame(height: 130, alignment: .bottom)

                if let selectedIndex {
                    let segment = geometry.size.width / CGFloat(values.count)
                    let tooltipWidth: CGFloat = 104
                    let centerX = segment * (CGFloat(selectedIndex) + 0.5)
                    let x = min(max(0, centerX - tooltipWidth / 2), geometry.size.width - tooltipWidth)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labels[selectedIndex]).font(.caption2).foregroundStyle(.white.opacity(0.65))
                        Text(amounts[selectedIndex]).font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(color: Theme.ink.opacity(0.22), radius: 12, y: 6)
                    .offset(x: x, y: -10)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let segment = geometry.size.width / CGFloat(values.count)
                        let index = min(max(Int(gesture.location.x / segment), 0), values.count - 1)
                        if selectedIndex != index {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                                selectedIndex = index
                            }
                        }
                    }
            )
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Interactive chart")
        .accessibilityValue(selectedIndex.map { "\(labels[$0]), \(amounts[$0])" } ?? "Drag across the chart for details")
    }
}

private struct AnimatedCurrencyText: View {
    let value: Double
    let fontSize: CGFloat
    let color: Color
    var fractionDigits = 0
    @State private var displayedValue = 0.0

    var body: some View {
        Text(displayedValue, format: .currency(code: "USD").precision(.fractionLength(fractionDigits)))
            .font(.system(size: fontSize, weight: .heavy))
            .foregroundStyle(color)
            .contentTransition(.numericText(value: displayedValue))
            .onAppear {
                withAnimation(.spring(response: 1.05, dampingFraction: 0.82)) {
                    displayedValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) {
                    displayedValue = newValue
                }
            }
    }
}

private struct ItemRollupCard: View {
    let item: ItemRollup
    let openOrders: () -> Void

    var body: some View {
        Button(action: openOrders) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Image(item.orders.first?.productImage ?? "WellnessEssentials")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.ink)
                        Text("\(item.orders.count) orders across \(Set(item.orders.map(\.channel)).count) channels")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    ItemStat(value: "\(item.units)", label: "Units")
                    ItemStat(value: item.revenue.formatted(.currency(code: "USD").precision(.fractionLength(0))), label: "Revenue")
                    ItemStat(value: "\(item.orders.filter { $0.state == .ready }.count)", label: "Ready")
                }
                HStack(spacing: -5) {
                    ForEach(Array(Set(item.orders.map(\.channel))).prefix(4), id: \.self) { channel in
                        ChannelIcon(channel: channel, size: 28)
                    }
                    Spacer()
                    Text("View matching orders")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .premiumCard()
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct ItemStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(Theme.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.softGray, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChannelIcon: View {
    let channel: SalesChannel
    let size: CGFloat

    var body: some View {
        Group {
            if let asset = channel.logoAsset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(channel.tint)
                    .padding(size * 0.22)
            } else {
                Image(systemName: channel.symbol)
                    .font(.system(size: size * 0.40, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: min(10, size * 0.24)))
        .overlay(RoundedRectangle(cornerRadius: min(10, size * 0.24)).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 3)
    }
}

/*
 Legacy button bars and symbol marketplace tiles were replaced with gesture-driven
 chart tracking and vector marketplace assets.
 */

private struct ChannelProgress: View {
    let channel: SalesChannel
    let amount: String
    let percent: CGFloat

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                ChannelIcon(channel: channel, size: 30)
                Text(channel.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                Text(amount).font(.subheadline.weight(.heavy))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.softGray)
                    Capsule().fill(channel.tint).frame(width: geometry.size.width * percent)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct StatusPill: View {
    let state: OrderState

    var body: some View {
        Text(state.rawValue).font(.caption2.weight(.bold)).foregroundStyle(state.tint)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(state.tint.opacity(0.1), in: Capsule())
    }
}

private struct SummaryCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.heavy)).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }
}

private struct ActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint)
                    .frame(width: 38, height: 38).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12).background(Theme.softGray.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct CompactOrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: 11) {
            ChannelIcon(channel: order.channel, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(order.customer).font(.subheadline.weight(.bold))
                Text("\(order.id) • \(order.items)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(order.total).font(.subheadline.weight(.heavy))
                StatusPill(state: order.state)
            }
        }
    }
}

private struct DetailGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            content
        }
        .premiumCard()
    }
}

private struct DetailLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 32, height: 32).background(Theme.softBlue, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct FinanceMetric: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(value).font(.title3.weight(.heavy)).minimumScaleFactor(0.75)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(detail).font(.caption2).foregroundStyle(tint)
        }
        .premiumCard()
    }
}

private struct ROIChannel: View {
    let name: String
    let value: String
    let change: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(value).font(.title3.weight(.heavy))
            Text(name).font(.caption.weight(.semibold))
            Text(change).font(.caption2).foregroundStyle(change.hasPrefix("+") ? Theme.green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Theme.softGray.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TopToastBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white.opacity(0.82))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Theme.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .padding(.horizontal, 16)
    }
}

private enum ToastCenter {
    static func show(_ text: String, toast: Binding<String?>) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { toast.wrappedValue = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toast.wrappedValue == text {
                withAnimation(.easeOut(duration: 0.2)) { toast.wrappedValue = nil }
            }
        }
    }
}

#Preview {
    DashboardView()
}
