import AppIntents
import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Query(sort: \ExpenseRecord.date, order: .reverse)
    private var expenses: [ExpenseRecord]

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var weeklyCoverImageData: Data?

    init() {
        _weeklyCoverImageData = State(initialValue: WeeklyCoverStore.load())
        #if canImport(UIKit)
        configureNavigationBarAppearance()
        #endif
    }

    private var selectedTheme: AppTheme {
        colorScheme == .dark ? .midnight : .sandstone
    }

    var body: some View {
        ZStack {
            selectedTheme.background

            TabView {
                TransactionsView(
                    expenses: expenses,
                    theme: selectedTheme,
                    weeklyCoverImageData: weeklyCoverImageData
                )
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle.fill")
                }

                SettingsView(
                    theme: selectedTheme,
                    weeklyCoverImageData: $weeklyCoverImageData
                )
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .toolbarBackground(.hidden, for: .tabBar)
        }
        .tint(selectedTheme.accent)
        .font(.system(.body, design: .default))
    }
}

private struct TransactionsView: View {
    let expenses: [ExpenseRecord]
    let theme: AppTheme
    let weeklyCoverImageData: Data?

    @State private var query = ""
    @State private var showsCompactTitle = false

    private var currentWeekExpenses: [ExpenseRecord] {
        expenses.filter {
            Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear)
        }
    }

    private var currentWeekTotal: Double {
        currentWeekExpenses.reduce(0) { $0 + $1.amount }
    }

    private var filteredExpenses: [ExpenseRecord] {
        guard !query.isEmpty else { return expenses }

        return expenses.filter {
            $0.merchant.localizedStandardContains(query)
                || $0.expenseCategory.title.localizedStandardContains(query)
                || $0.cardName.localizedStandardContains(query)
        }
    }

    private var groupedExpenses: [ExpenseMonth] {
        let groups = Dictionary(grouping: filteredExpenses) {
            $0.date.formatted(.dateTime.month(.wide).year())
        }

        return groups
            .map { title, items in
                ExpenseMonth(
                    title: title,
                    expenses: items.sorted { $0.date > $1.date }
                )
            }
            .sorted {
                ($0.expenses.first?.date ?? .distantPast)
                    > ($1.expenses.first?.date ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    NavigationLink {
                        WeeklyCategoryView(
                            expenses: currentWeekExpenses,
                            theme: theme
                        )
                    } label: {
                        WeeklySummaryCard(
                            amount: currentWeekTotal,
                            count: currentWeekExpenses.count,
                            theme: theme,
                            coverImageData: weeklyCoverImageData
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows spending by category for this week")

                    if expenses.isEmpty {
                        EmptyTransactionsCard(theme: theme)
                    } else {
                        SearchField(query: $query, theme: theme)

                        if groupedExpenses.isEmpty {
                            NoSearchResultsCard(theme: theme)
                        } else {
                            ForEach(groupedExpenses) { month in
                                TransactionMonthSection(
                                    month: month,
                                    theme: theme
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .swipeActionsContainer()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 48
            } action: { _, isCollapsed in
                showsCompactTitle = isCollapsed
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Transactions")
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Text("Transactions")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ToolbarItem(placement: .title) {
                    Text("Transactions")
                        .font(.system(.headline, design: .serif, weight: .bold))
                        .opacity(showsCompactTitle ? 1 : 0)
                        .accessibilityHidden(!showsCompactTitle)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct GrainOverlay: View {
    let theme: AppTheme

    var body: some View {
        Image(uiImage: GrainTexture.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(theme == .midnight ? 0.08 : 0.065)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }
}

private enum GrainTexture {
    static let image: UIImage = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size)

        var seed: UInt64 = 0x4d595f475241494e
        func nextRandom() -> UInt8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 56)
        }

        for i in 0..<pixels.count {
            pixels[i] = nextRandom()
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let cgImage = context.makeImage() else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }()
}

private struct WeeklySummaryCard: View {
    let amount: Double
    let count: Int
    let theme: AppTheme
    let coverImageData: Data?

    private var coverImage: UIImage? {
        coverImageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Spent this week", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Text(amount, format: .currency(code: "EUR"))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            HStack {
                Image(systemName: count == 0 ? "tray" : "checkmark.circle.fill")
                    .foregroundStyle(theme.highlight)
                Text(count == 0 ? "No data received yet" : "\(count) transactions recorded")
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.18),
                                .black.opacity(0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                theme.summaryGradient
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: theme.accent.opacity(0.22), radius: 18, y: 10)
    }
}

private struct WeeklyCategoryView: View {
    let expenses: [ExpenseRecord]
    let theme: AppTheme

    private var categoryTotals: [WeeklyCategoryTotal] {
        ExpenseCategory.allCases.compactMap { category in
            let amount = expenses
                .filter { $0.expenseCategory == category }
                .reduce(0) { $0 + $1.amount }

            return amount > 0
                ? WeeklyCategoryTotal(category: category, amount: amount)
                : nil
        }
        .sorted { $0.amount > $1.amount }
    }

    private var weekDescription: String {
        guard let interval = Calendar.current.dateInterval(
            of: .weekOfYear,
            for: .now
        ) else {
            return "Current week"
        }

        let finalDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: interval.end
        ) ?? interval.end

        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day()))–\(finalDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(weekDescription.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text(
                        expenses.reduce(0) { $0 + $1.amount },
                        format: .currency(code: "EUR")
                    )
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                }

                if categoryTotals.isEmpty {
                    ContentUnavailableView(
                        "No spending this week",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Transactions from this week will be grouped here by their selected glyph.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(theme.cardColor, in: .rect(cornerRadius: 24))
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Most spent categories")
                            .font(.system(.title3, design: .serif, weight: .bold))

                        Chart(categoryTotals) { total in
                            BarMark(
                                x: .value("Amount", total.amount),
                                y: .value("Category", total.category.title)
                            )
                            .foregroundStyle(total.category.color.gradient)
                            .cornerRadius(6)
                        }
                        .frame(height: max(220, CGFloat(categoryTotals.count) * 48))

                        Divider()

                        ForEach(categoryTotals) { total in
                            HStack(spacing: 12) {
                                Image(systemName: total.category.symbol)
                                    .foregroundStyle(total.category.color)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        total.category.color.opacity(0.14),
                                        in: Circle()
                                    )

                                Text(total.category.title)
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Text(
                                    total.amount,
                                    format: .currency(code: "EUR")
                                )
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(20)
                    .background(theme.cardColor, in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(theme.borderColor)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Weekly spending")
        .toolbarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct WeeklyCategoryTotal: Identifiable {
    let category: ExpenseCategory
    let amount: Double

    var id: ExpenseCategory { category }
}

private struct EmptyTransactionsCard: View {
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(theme.accent)

            Text("Ledger is running")
                .font(.system(.title2, design: .serif, weight: .bold))

            Text("There are no transactions to display yet. Add one manually, import a CSV file, or connect the Shortcuts automation from Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Open Settings to add data", systemImage: "arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(theme.cardColor, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.borderColor)
        }
    }
}

private struct SearchField: View {
    @Binding var query: String
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Merchant, category or card", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    query = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(theme.cardColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.borderColor)
        }
    }
}

private struct NoSearchResultsCard: View {
    let theme: AppTheme

    var body: some View {
        ContentUnavailableView(
            "No matching transactions",
            systemImage: "magnifyingglass",
            description: Text("Try a different merchant, category, or card.")
        )
        .frame(maxWidth: .infinity)
        .padding()
        .background(theme.cardColor, in: .rect(cornerRadius: 24))
    }
}

private struct TransactionMonthSection: View {
    let month: ExpenseMonth
    let theme: AppTheme

    @Environment(\.modelContext)
    private var modelContext

    @State private var editingExpense: ExpenseRecord?
    @State private var selectedExpense: ExpenseRecord?
    @State private var deletionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.title)
                    .font(.system(.title3, design: .serif, weight: .bold))

                Spacer()

                Text(month.total, format: .currency(code: "EUR"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(month.expenses) { expense in
                    Button {
                        selectedExpense = expense
                    } label: {
                        ExpenseRow(expense: expense)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .accessibilityHint("Shows transaction details")
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: true
                    ) {
                        Button(role: .destructive) {
                            delete(expense)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingExpense = expense
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(theme.accent)
                    }

                    if expense.persistentModelID != month.expenses.last?.persistentModelID {
                        Divider()
                            .padding(.leading, 75)
                    }
                }
            }
            .background(theme.cardColor, in: .rect(cornerRadius: 24))
            .clipShape(.rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(theme.borderColor)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(
                expense: expense,
                theme: theme
            )
            .presentationBackground {
                theme.background
            }
        }
        .sheet(item: $selectedExpense) { expense in
            TransactionDetailView(
                expense: expense,
                theme: theme
            )
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                theme.background
            }
        }
        .alert(
            "Couldn’t delete transaction",
            isPresented: Binding(
                get: { deletionError != nil },
                set: { isPresented in
                    if !isPresented {
                        deletionError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private func delete(_ expense: ExpenseRecord) {
        do {
            modelContext.delete(expense)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deletionError = error.localizedDescription
        }
    }
}

private struct ExpenseRow: View {
    let expense: ExpenseRecord

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: expense.expenseCategory.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(expense.expenseCategory.color)
                .frame(width: 42, height: 42)
                .background(expense.expenseCategory.color.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.merchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(expense.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(expense.amount, format: .currency(code: "EUR"))
                    .font(.subheadline.weight(.semibold))

                Text(expense.cardName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct TransactionDetailView: View {
    let expense: ExpenseRecord
    let theme: AppTheme

    @Environment(\.dismiss)
    private var dismiss

    @State private var isShowingEditor = false

    private var sourceDescription: String {
        switch ExpenseSource(rawValue: expense.sourceRawValue) {
        case .shortcut:
            "Shortcuts automation"
        case .manual:
            "Added manually"
        case .csv:
            "CSV import"
        case .notes:
            "Notes import"
        case nil:
            "Unknown source"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: expense.expenseCategory.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(expense.expenseCategory.color)
                            .frame(width: 52, height: 52)
                            .background(
                                expense.expenseCategory.color.opacity(0.14),
                                in: Circle()
                            )

                        Text(expense.amount, format: .currency(code: "EUR"))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)

                        Text(expense.merchant)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)

                        Text(expense.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        TransactionDetailRow(
                            title: "Card",
                            value: expense.cardName,
                            systemImage: "creditcard.fill"
                        )

                        Divider()
                            .padding(.leading, 48)

                        TransactionDetailRow(
                            title: "Category",
                            value: expense.expenseCategory.title,
                            systemImage: expense.expenseCategory.symbol
                        )

                        Divider()
                            .padding(.leading, 48)

                        TransactionDetailRow(
                            title: "Added through",
                            value: sourceDescription,
                            systemImage: "arrow.down.doc.fill"
                        )
                    }
                    .padding(.horizontal, 18)
                    .background(theme.cardColor, in: .rect(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(theme.borderColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Transaction")
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Transaction")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isShowingEditor = true
                } label: {
                    Label("Edit transaction", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .sheet(isPresented: $isShowingEditor) {
                EditExpenseView(
                    expense: expense,
                    theme: theme
                )
                .presentationBackground {
                    theme.background
                }
            }
        }
        .presentationBackground {
            theme.background
        }
    }
}

private struct TransactionDetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }
}

private struct ExpenseMonth: Identifiable {
    let title: String
    let expenses: [ExpenseRecord]

    var id: String { title }
    var total: Double { expenses.reduce(0) { $0 + $1.amount } }
}

private struct SettingsView: View {
    let theme: AppTheme
    @Binding var weeklyCoverImageData: Data?

    @State private var isShowingManualEntry = false
    @State private var isShowingNotesImport = false
    @State private var isShowingCSVImporter = false
    @State private var isShowingImportAlert = false
    @State private var importMessage = ""
    @State private var isImporting = false
    @State private var showsCompactTitle = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    WeeklyCoverSettingsCard(
                        theme: theme,
                        coverImageData: $weeklyCoverImageData
                    )

                    ImportSettingsCard(
                        theme: theme,
                        isImporting: isImporting,
                        onManualEntry: { isShowingManualEntry = true },
                        onNotesImport: { isShowingNotesImport = true },
                        onCSVImport: { isShowingCSVImporter = true }
                    )

                    CSVFormatCard(theme: theme)

                    AutomationSettingsCard(theme: theme)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 48
            } action: { _, isCollapsed in
                showsCompactTitle = isCollapsed
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Text("Settings")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ToolbarItem(placement: .title) {
                    Text("Settings")
                        .font(.system(.headline, design: .serif, weight: .bold))
                        .opacity(showsCompactTitle ? 1 : 0)
                        .accessibilityHidden(!showsCompactTitle)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingManualEntry) {
                ManualExpenseView(theme: theme) { message in
                    showImportResult(message)
                }
                .presentationBackground {
                    theme.background
                }
            }
            .sheet(isPresented: $isShowingNotesImport) {
                NoteImportView(theme: theme) { message in
                    showImportResult(message)
                }
                .presentationBackground {
                    theme.background
                }
            }
            .fileImporter(
                isPresented: $isShowingCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Import result", isPresented: $isShowingImportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                showImportResult("No CSV file was selected.")
                return
            }
            importCSV(from: url)
        case .failure(let error):
            showImportResult(error.localizedDescription)
        }
    }

    private func importCSV(from url: URL) {
        isImporting = true
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()

        Task {
            defer {
                if hasSecurityAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let drafts = try await Task.detached(priority: .userInitiated) {
                    try CSVExpenseImporter.parse(url: url)
                }.value

                let repository = ExpenseRepository(
                    modelContainer: ExpensePersistence.container
                )
                let result = try await repository.importExpenses(drafts)

                await MainActor.run {
                    isImporting = false
                    showImportResult(
                        "Imported \(result.importedCount) transactions. Skipped \(result.duplicateCount) duplicates."
                    )
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    showImportResult(error.localizedDescription)
                }
            }
        }
    }

    private func showImportResult(_ message: String) {
        importMessage = message
        isShowingImportAlert = true
    }
}

private struct ImportSettingsCard: View {
    let theme: AppTheme
    let isImporting: Bool
    let onManualEntry: () -> Void
    let onNotesImport: () -> Void
    let onCSVImport: () -> Void

    var body: some View {
        SettingsCard(
            title: "Import transactions",
            subtitle: "Add one expense or import a prepared file",
            theme: theme
        ) {
            Button(action: onManualEntry) {
                SettingsActionLabel(
                    title: "Add manually",
                    detail: "Enter merchant, amount, card, and category",
                    symbol: "plus.circle.fill",
                    theme: theme
                )
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: onNotesImport) {
                SettingsActionLabel(
                    title: "Import from Notes",
                    detail: "Paste a note and extract expenses with Apple Intelligence",
                    symbol: "apple.intelligence",
                    theme: theme
                )
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: onCSVImport) {
                SettingsActionLabel(
                    title: isImporting ? "Importing…" : "Import CSV",
                    detail: "Select a UTF-8 comma-separated file",
                    symbol: "tablecells.fill",
                    theme: theme
                )
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
        }
    }
}

private struct WeeklyCoverSettingsCard: View {
    let theme: AppTheme
    @Binding var coverImageData: Data?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    private var coverImage: UIImage? {
        coverImageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        SettingsCard(
            title: "Weekly spending cover",
            subtitle: "Personalize the summary card on Transactions",
            theme: theme
        ) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(theme.borderColor)
                    }
                    .accessibilityLabel("Current weekly spending cover")
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.summaryGradient)
                    .frame(height: 100)
                    .overlay {
                        Label("Default cover", systemImage: "chart.bar.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Default weekly spending cover")
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                SettingsActionLabel(
                    title: coverImageData == nil ? "Choose photo" : "Change photo",
                    detail: "Select an image from your photo library",
                    symbol: "photo.on.rectangle.angled",
                    theme: theme
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto)

            if isLoadingPhoto {
                ProgressView("Preparing cover…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if coverImageData != nil {
                Divider()

                Button(role: .destructive) {
                    removeCoverPhoto()
                } label: {
                    Label("Remove photo and restore default", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
            }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            guard let newPhoto else { return }
            loadCoverPhoto(from: newPhoto)
        }
        .alert(
            "Couldn’t update cover",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadCoverPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        errorMessage = nil

        Task {
            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                    throw WeeklyCoverError.unsupportedImage
                }

                let preparedData = try WeeklyCoverStore.savePhotoData(sourceData)

                coverImageData = preparedData
                isLoadingPhoto = false
            } catch {
                selectedPhoto = nil
                isLoadingPhoto = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeCoverPhoto() {
        do {
            try WeeklyCoverStore.remove()
            selectedPhoto = nil
            coverImageData = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NoteImportView: View {
    let theme: AppTheme
    let onCompletion: (String) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var noteText = ""
    @State private var candidates: [NoteTransactionCandidate] = []
    @State private var isExtracting = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var modelAvailabilityMessage: String? {
        NoteTransactionExtractor.availabilityMessage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Transaction note")
                } header: {
                    Text("Paste note text")
                } footer: {
                    Text("Copy text from Apple Notes and paste it here. Processing stays on this device. Always review extracted details before importing.")
                }

                if let modelAvailabilityMessage {
                    Section("Apple Intelligence") {
                        Label(modelAvailabilityMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if !candidates.isEmpty {
                    Section {
                        ForEach($candidates) { $candidate in
                            DisclosureGroup {
                                TextField("Merchant", text: $candidate.merchant)

                                TextField(
                                    "Amount",
                                    value: $candidate.amount,
                                    format: .number.precision(.fractionLength(2))
                                )
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif

                                DatePicker(
                                    "Date",
                                    selection: $candidate.date,
                                    displayedComponents: [.date, .hourAndMinute]
                                )

                                TextField("Card name", text: $candidate.cardName)

                                Picker("Category & glyph", selection: $candidate.category) {
                                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                                        Label(category.title, systemImage: category.symbol)
                                            .tag(category)
                                    }
                                }

                                Button("Remove transaction", systemImage: "trash", role: .destructive) {
                                    removeCandidate(candidate.id)
                                }
                            } label: {
                                HStack {
                                    Label(candidate.merchant, systemImage: candidate.category.symbol)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(candidate.amount, format: .currency(code: "EUR"))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    } header: {
                        Text("Review extracted transactions")
                    } footer: {
                        Text("Apple Intelligence can make mistakes. Check the merchant, amount, date, card, and category for every transaction.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Button {
                            extractTransactions()
                        } label: {
                            if isExtracting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Extract transactions", systemImage: "apple.intelligence")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(
                            noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || modelAvailabilityMessage != nil
                                || isExtracting
                        )
                    } else {
                        Button {
                            importTransactions()
                        } label: {
                            if isImporting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Import \(candidates.count) transactions")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isImporting)

                        Button("Start over", role: .cancel) {
                            candidates = []
                            errorMessage = nil
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Import from Notes")
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Import from Notes")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground {
            theme.background
        }
    }

    private func extractTransactions() {
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        isExtracting = true
        errorMessage = nil

        Task {
            do {
                let extracted = try await NoteTransactionExtractor.extract(from: note)
                isExtracting = false

                guard !extracted.isEmpty else {
                    errorMessage = "No clear expense transactions were found. Add merchant names, amounts, and dates, then try again."
                    return
                }

                candidates = extracted
            } catch {
                isExtracting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importTransactions() {
        guard candidates.allSatisfy({
            !$0.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.amount > 0
                && $0.amount.isFinite
        }) else {
            errorMessage = "Each transaction needs a merchant and a positive amount."
            return
        }

        isImporting = true
        errorMessage = nil
        let drafts = candidates.map(\.expenseDraft)

        Task {
            do {
                let repository = ExpenseRepository(
                    modelContainer: ExpensePersistence.container
                )
                let result = try await repository.importExpenses(drafts)
                isImporting = false
                onCompletion(
                    "Imported \(result.importedCount) transactions from Notes. Skipped \(result.duplicateCount) duplicates."
                )
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeCandidate(_ id: NoteTransactionCandidate.ID) {
        candidates.removeAll { $0.id == id }
    }
}

private struct SettingsActionLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accent.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

private struct CSVFormatCard: View {
    let theme: AppTheme

    var body: some View {
        SettingsCard(
            title: "Required CSV format",
            subtitle: "The first row must use these exact column names",
            theme: theme
        ) {
            Text(CSVExpenseImporter.requiredHeader)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                CSVRule(label: "date", value: "ISO 8601 or YYYY-MM-DD")
                CSVRule(label: "merchant", value: "Text; quote names containing commas")
                CSVRule(label: "amount", value: "Positive number using a decimal point")
                CSVRule(label: "card", value: "Readable card name")
                CSVRule(label: "category", value: ExpenseCategory.allCases.map(\.rawValue).joined(separator: ", "))
            }

            Text("Example")
                .font(.caption.weight(.semibold))

            Text("2026-09-26,Corner Café,12.50,Personal Visa,dining")
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Files must be UTF-8 encoded. Use double quotes around any field containing a comma, and escape a quote by writing it twice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CSVRule: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AutomationSettingsCard: View {
    let theme: AppTheme

    var body: some View {
        SettingsCard(
            title: "Shortcuts automation",
            subtitle: "For supported Apple Wallet transaction triggers",
            theme: theme
        ) {
            Text("Create a Transaction automation in Shortcuts, add Ledger’s “Add Expense” action, and map Amount and Merchant directly from Shortcut Input. Use Other when no reliable category is supplied.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            #if os(iOS)
            ShortcutsLink()
                .shortcutsLinkStyle(.automatic)
            #endif
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let theme: AppTheme
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        theme: AppTheme,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title3, design: .serif, weight: .bold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(theme.cardColor, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.borderColor)
        }
    }
}

private struct EditExpenseView: View {
    let expense: ExpenseRecord
    let theme: AppTheme

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @State private var merchant = ""
    @State private var amount = ""
    @State private var transactionDate = Date.now
    @State private var cardName = ""
    @State private var category = ExpenseCategory.other
    @State private var validationMessage: String?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Merchant", text: $merchant)

                    TextField("Amount", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif

                    DatePicker(
                        "Date",
                        selection: $transactionDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Details") {
                    TextField("Card name", text: $cardName)

                    Picker("Category & glyph", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { option in
                            Label(option.title, systemImage: option.symbol)
                                .tag(option)
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Edit transaction")
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit transaction")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .onAppear {
                loadExpenseOnce()
            }
        }
        .presentationBackground {
            theme.background
        }
    }

    private func loadExpenseOnce() {
        guard !didLoad else { return }
        merchant = expense.merchant
        amount = expense.amount.formatted(.number.precision(.fractionLength(2)))
        transactionDate = expense.date
        cardName = expense.cardName
        category = expense.expenseCategory
        didLoad = true
    }

    private func save() {
        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCard = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAmount = amount.replacingOccurrences(of: ",", with: ".")

        guard !cleanMerchant.isEmpty else {
            validationMessage = "Enter a merchant."
            return
        }

        guard let parsedAmount = Double(normalizedAmount),
              parsedAmount > 0,
              parsedAmount.isFinite else {
            validationMessage = "Enter a positive amount."
            return
        }

        expense.merchant = cleanMerchant
        expense.amount = parsedAmount
        expense.date = transactionDate
        expense.cardName = cleanCard.isEmpty ? "Unknown card" : cleanCard
        expense.categoryRawValue = category.rawValue
        expense.fingerprint = ExpenseFingerprint.make(
            merchant: expense.merchant,
            amount: expense.amount,
            date: expense.date,
            cardName: expense.cardName
        )

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = error.localizedDescription
        }
    }
}

private struct ManualExpenseView: View {
    let theme: AppTheme
    let onCompletion: (String) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var merchant = ""
    @State private var amount = ""
    @State private var transactionDate = Date.now
    @State private var cardName = ""
    @State private var category = ExpenseCategory.other
    @State private var validationMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Merchant", text: $merchant)

                    TextField("Amount", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif

                    DatePicker(
                        "Date",
                        selection: $transactionDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Details") {
                    TextField("Card name", text: $cardName)

                    Picker("Category & glyph", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { option in
                            Label(option.title, systemImage: option.symbol)
                                .tag(option)
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Add transaction")
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add transaction")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationBackground {
            theme.background
        }
    }

    private func save() {
        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCard = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAmount = amount.replacingOccurrences(of: ",", with: ".")

        guard !cleanMerchant.isEmpty else {
            validationMessage = "Enter a merchant."
            return
        }

        guard let parsedAmount = Double(normalizedAmount),
              parsedAmount > 0,
              parsedAmount.isFinite else {
            validationMessage = "Enter a positive amount."
            return
        }

        isSaving = true
        validationMessage = nil

        let repository = ExpenseRepository(
            modelContainer: ExpensePersistence.container
        )

        Task {
            do {
                let inserted = try await repository.addExpense(
                    merchant: cleanMerchant,
                    amount: parsedAmount,
                    date: transactionDate,
                    category: category,
                    cardName: cleanCard.isEmpty ? "Unknown card" : cleanCard,
                    source: .manual
                )

                await MainActor.run {
                    onCompletion(
                        inserted
                            ? "The transaction was added."
                            : "That transaction is already in Ledger."
                    )
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    validationMessage = error.localizedDescription
                }
            }
        }
    }
}

private enum AppTheme {
    case midnight
    case sandstone

    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.48, green: 0.56, blue: 1.0)
        case .sandstone: Color(red: 0.58, green: 0.31, blue: 0.18)
        }
    }

    var highlight: Color {
        switch self {
        case .midnight: .mint
        case .sandstone: Color(red: 1.0, green: 0.82, blue: 0.56)
        }
    }

    var cardColor: Color {
        switch self {
        case .midnight: Color(red: 0.09, green: 0.11, blue: 0.17).opacity(0.92)
        case .sandstone: Color(red: 0.97, green: 0.93, blue: 0.84).opacity(0.94)
        }
    }

    var borderColor: Color {
        switch self {
        case .midnight: .white.opacity(0.09)
        case .sandstone: .black.opacity(0.08)
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.075),
                    Color(red: 0.055, green: 0.07, blue: 0.13),
                    Color(red: 0.08, green: 0.045, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sandstone:
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.89, blue: 0.78),
                    Color(red: 0.98, green: 0.95, blue: 0.88),
                    Color(red: 0.90, green: 0.83, blue: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    var background: some View {
        ZStack {
            gradient
                .ignoresSafeArea()

            GrainOverlay(theme: self)
        }
        .ignoresSafeArea()
    }

    var summaryGradient: LinearGradient {
        switch self {
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.20, blue: 0.42),
                    Color(red: 0.34, green: 0.20, blue: 0.47)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sandstone:
            LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.24, blue: 0.15),
                    Color(red: 0.68, green: 0.42, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private extension ExpenseRecord {
    var expenseCategory: ExpenseCategory {
        ExpenseCategory(rawValue: categoryRawValue) ?? .other
    }
}

private extension ExpenseCategory {
    var title: String {
        switch self {
        case .groceries: "Groceries"
        case .transport: "Transport"
        case .dining: "Dining"
        case .shopping: "Shopping"
        case .leisure: "Leisure"
        case .health: "Health"
        case .travel: "Travel"
        case .bills: "Bills"
        case .other: "Other"
        case .clothing: "Clothing"
        case .utilities: "Utilities"
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "basket.fill"
        case .transport: "car.fill"
        case .dining: "fork.knife"
        case .shopping: "bag.fill"
        case .leisure: "ticket.fill"
        case .health: "cross.case.fill"
        case .travel: "airplane"
        case .bills: "doc.text.fill"
        case .other: "square.grid.2x2.fill"
        case .clothing: "tshirt.fill"
        case .utilities: "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .groceries: .green
        case .transport: .blue
        case .dining: .orange
        case .shopping: .purple
        case .leisure: .pink
        case .health: .red
        case .travel: .teal
        case .bills: .indigo
        case .other: .gray
        case .clothing: .purple
        case .utilities: .yellow
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: ExpenseRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(
        ExpenseRecord(
            fingerprint: "1",
            merchant: "Corner Café",
            amount: 12.50,
            date: .now,
            category: .dining,
            cardName: "Personal Visa",
            source: .manual
        )
    )
    container.mainContext.insert(
        ExpenseRecord(
            fingerprint: "2",
            merchant: "Supermarket",
            amount: 45.80,
            date: .now.addingTimeInterval(-3600),
            category: .groceries,
            cardName: "Personal Visa",
            source: .manual
        )
    )
    return ContentView()
        .modelContainer(container)
}
#Preview("Detail Light") {
    TransactionDetailView(
        expense: ExpenseRecord(
            fingerprint: "1",
            merchant: "Conad City",
            amount: 14.03,
            date: .now,
            category: .shopping,
            cardName: "Unknown card",
            source: .notes
        ),
        theme: .sandstone
    )
}

#Preview("Detail Dark") {
    TransactionDetailView(
        expense: ExpenseRecord(
            fingerprint: "1",
            merchant: "Conad City",
            amount: 14.03,
            date: .now,
            category: .shopping,
            cardName: "Unknown card",
            source: .notes
        ),
        theme: .midnight
    )
    .preferredColorScheme(.dark)
}
