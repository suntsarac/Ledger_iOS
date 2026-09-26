import Foundation

enum CSVExpenseImporter {
    nonisolated static let requiredHeader = "date,merchant,amount,card,category"

    nonisolated static func parse(url: URL) throws -> [ExpenseDraft] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVImportError.notUTF8
        }
        return try parse(text: text)
    }

    nonisolated static func parse(text: String) throws -> [ExpenseDraft] {
        let rows = try rows(in: text)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard let headerRow = rows.first else {
            throw CSVImportError.emptyFile
        }

        let headers = headerRow.map(normalizeHeader)
        let requiredHeaders = ["date", "merchant", "amount", "card", "category"]

        guard headers == requiredHeaders else {
            throw CSVImportError.invalidHeader
        }

        return try rows.dropFirst().enumerated().map { offset, row in
            let lineNumber = offset + 2
            guard row.count == headers.count else {
                throw CSVImportError.invalidColumnCount(line: lineNumber)
            }

            let values = Dictionary(uniqueKeysWithValues: zip(headers, row))
            let merchant = values["merchant", default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !merchant.isEmpty else {
                throw CSVImportError.missingMerchant(line: lineNumber)
            }

            let amountText = values["amount", default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = Double(amountText), amount > 0, amount.isFinite else {
                throw CSVImportError.invalidAmount(line: lineNumber)
            }

            let dateText = values["date", default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = parseDate(dateText) else {
                throw CSVImportError.invalidDate(line: lineNumber)
            }

            let categoryText = normalizeHeader(values["category", default: ""])
            guard let category = ExpenseCategory(rawValue: categoryText) else {
                throw CSVImportError.invalidCategory(line: lineNumber)
            }

            let card = values["card", default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return ExpenseDraft(
                merchant: merchant,
                amount: amount,
                date: date,
                category: category,
                cardName: card.isEmpty ? "Unknown card" : card,
                source: .csv
            )
        }
    }

    nonisolated private static func normalizeHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current
        return dayFormatter.date(from: value)
    }

    nonisolated private static func rows(in text: String) throws -> [[String]] {
        let scalars = Array(text.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar == "\"" {
                if isInsideQuotes,
                   index + 1 < scalars.count,
                   scalars[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }

                isInsideQuotes.toggle()
            } else if scalar == ",", !isInsideQuotes {
                row.append(field)
                field = ""
            } else if (scalar == "\n" || scalar == "\r"), !isInsideQuotes {
                if scalar == "\r",
                   index + 1 < scalars.count,
                   scalars[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(Character(String(scalar)))
            }

            index += 1
        }

        guard !isInsideQuotes else {
            throw CSVImportError.unclosedQuote
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}

enum CSVImportError: LocalizedError {
    case emptyFile
    case notUTF8
    case invalidHeader
    case invalidColumnCount(line: Int)
    case missingMerchant(line: Int)
    case invalidAmount(line: Int)
    case invalidDate(line: Int)
    case invalidCategory(line: Int)
    case unclosedQuote

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "The CSV file is empty."
        case .notUTF8:
            "The CSV file must use UTF-8 text encoding."
        case .invalidHeader:
            "The CSV header must be: \(CSVExpenseImporter.requiredHeader)"
        case .invalidColumnCount(let line):
            "Line \(line) does not contain exactly five columns."
        case .missingMerchant(let line):
            "Line \(line) is missing a merchant."
        case .invalidAmount(let line):
            "Line \(line) has an invalid amount. Use a positive number with a decimal point."
        case .invalidDate(let line):
            "Line \(line) has an invalid date. Use ISO 8601 or YYYY-MM-DD."
        case .invalidCategory(let line):
            "Line \(line) has an unsupported category."
        case .unclosedQuote:
            "The CSV contains an unclosed quoted field."
        }
    }
}
