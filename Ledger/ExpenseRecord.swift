import Foundation
import SwiftData

@Model
final class ExpenseRecord {
    @Attribute(.unique) var fingerprint: String
    var merchant: String
    var amount: Double
    var date: Date
    var categoryRawValue: String
    var cardName: String
    var sourceRawValue: String
    var createdAt: Date

    init(
        fingerprint: String,
        merchant: String,
        amount: Double,
        date: Date,
        category: ExpenseCategory,
        cardName: String,
        source: ExpenseSource
    ) {
        self.fingerprint = fingerprint
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.categoryRawValue = category.rawValue
        self.cardName = cardName
        self.sourceRawValue = source.rawValue
        self.createdAt = .now
    }
}

enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
    case groceries
    case transport
    case dining
    case shopping
    case leisure
    case health
    case travel
    case bills
    case other
    case clothing
    case utilities
}

enum ExpenseSource: String, Codable, Sendable {
    case shortcut
    case manual
    case csv
    case notes
}

struct ExpenseDraft: Sendable {
    let merchant: String
    let amount: Double
    let date: Date
    let category: ExpenseCategory
    let cardName: String
    let source: ExpenseSource
}

struct ExpenseImportResult: Sendable {
    let importedCount: Int
    let duplicateCount: Int
}

enum ExpensePersistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: ExpenseRecord.self)
        } catch {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let fallback = try? ModelContainer(
                for: ExpenseRecord.self,
                configurations: configuration
            ) else {
                fatalError("Unable to create the expense data store.")
            }
            return fallback
        }
    }()
}

enum ExpenseFingerprint {
    nonisolated static func make(
        merchant: String,
        amount: Double,
        date: Date,
        cardName: String
    ) -> String {
        let normalizedMerchant = normalize(merchant)
        let normalizedCard = normalize(cardName)
        let amountInCents = Int((amount * 100).rounded())
        let minute = Int(date.timeIntervalSince1970 / 60)

        return [
            normalizedMerchant,
            String(amountInCents),
            String(minute),
            normalizedCard
        ].joined(separator: "|")
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

@ModelActor
actor ExpenseRepository {
    @discardableResult
    func addExpense(
        merchant: String,
        amount: Double,
        date: Date,
        category: ExpenseCategory,
        cardName: String,
        source: ExpenseSource
    ) throws -> Bool {
        let result = try importExpenses([
            ExpenseDraft(
                merchant: merchant,
                amount: amount,
                date: date,
                category: category,
                cardName: cardName,
                source: source
            )
        ])
        return result.importedCount == 1
    }

    func importExpenses(_ drafts: [ExpenseDraft]) throws -> ExpenseImportResult {
        let existingRecords = try modelContext.fetch(FetchDescriptor<ExpenseRecord>())
        var fingerprints = Set(existingRecords.map(\.fingerprint))
        var importedCount = 0
        var duplicateCount = 0

        for draft in drafts {
            let fingerprint = ExpenseFingerprint.make(
                merchant: draft.merchant,
                amount: draft.amount,
                date: draft.date,
                cardName: draft.cardName
            )

            guard fingerprints.insert(fingerprint).inserted else {
                duplicateCount += 1
                continue
            }

            modelContext.insert(
                ExpenseRecord(
                    fingerprint: fingerprint,
                    merchant: draft.merchant,
                    amount: draft.amount,
                    date: draft.date,
                    category: draft.category,
                    cardName: draft.cardName,
                    source: draft.source
                )
            )
            importedCount += 1
        }

        if importedCount > 0 {
            try modelContext.save()
        }

        return ExpenseImportResult(
            importedCount: importedCount,
            duplicateCount: duplicateCount
        )
    }
}
