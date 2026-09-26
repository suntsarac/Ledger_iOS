import AppIntents
import Foundation

enum ShortcutExpenseCategory: String, AppEnum {
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Expense Category")

    static let caseDisplayRepresentations: [ShortcutExpenseCategory: DisplayRepresentation] = [
        .groceries: "Groceries",
        .transport: "Transport",
        .dining: "Dining",
        .shopping: "Shopping",
        .leisure: "Leisure",
        .health: "Health",
        .travel: "Travel",
        .bills: "Bills",
        .other: "Other",
        .clothing: "Clothing",
        .utilities: "Utilities"
    ]

    var expenseCategory: ExpenseCategory {
        ExpenseCategory(rawValue: rawValue) ?? .other
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription(
        "Records a transaction in Ledger. Designed for use with a Wallet transaction automation."
    )
    static let supportedModes: IntentModes = [.background]

    @Parameter(
        title: "Amount",
        description: "The transaction amount as a positive number."
    )
    var amount: Double

    @Parameter(
        title: "Merchant",
        description: "The merchant supplied by the transaction automation."
    )
    var merchant: String

    @Parameter(
        title: "Transaction Date",
        description: "The date and time of the transaction."
    )
    var transactionDate: Date?

    @Parameter(
        title: "Card",
        description: "A readable card name, such as Personal Visa."
    )
    var cardName: String?

    @Parameter(
        title: "Category",
        description: "An optional category. Leave this as Other when the automation has no reliable category.",
        default: .other
    )
    var category: ShortcutExpenseCategory

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) spent at \(\.$merchant)") {
            \.$transactionDate
            \.$cardName
            \.$category
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0, amount.isFinite else {
            throw AddExpenseIntentError.invalidAmount
        }

        let cleanedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMerchant = cleanedMerchant.isEmpty ? "Unknown merchant" : cleanedMerchant

        let cleanedCard = cardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedCard = cleanedCard.isEmpty ? "Apple Wallet" : cleanedCard

        do {
            let repository = await MainActor.run {
                ExpenseRepository(modelContainer: ExpensePersistence.container)
            }
            let inserted = try await repository.addExpense(
                merchant: resolvedMerchant,
                amount: amount,
                date: transactionDate ?? .now,
                category: category.expenseCategory,
                cardName: resolvedCard,
                source: .shortcut
            )

            if inserted {
                return .result(dialog: "Expense added to Ledger.")
            } else {
                return .result(dialog: "This expense is already in Ledger.")
            }
        } catch {
            throw AddExpenseIntentError.storageUnavailable
        }
    }
}

enum AddExpenseIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case storageUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount:
            "The expense amount must be greater than zero."
        case .storageUnavailable:
            "Ledger couldn’t save this expense. Open the app and try again."
        }
    }
}

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle.fill"
        )
    }
}
