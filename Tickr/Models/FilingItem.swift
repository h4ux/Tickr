import Foundation

/// One SEC EDGAR filing. Mirrors the fields we care about from the
/// `filings.recent` parallel arrays returned by the submissions endpoint.
struct FilingItem: Codable, Identifiable, Equatable {
    /// SEC accession numbers are globally unique, so we use them as our id.
    var id: String { accessionNumber }

    let symbol: String
    let cik: String
    /// e.g. "10-K", "8-K", "4", "S-1", "SC 13G/A"
    let form: String
    /// ISO-8601 date string ("2026-07-05") as returned by SEC.
    let filingDate: String
    /// e.g. "0001878057-26-000012"
    let accessionNumber: String
    /// Filename of the primary document within the filing, e.g. "example.htm".
    let primaryDocument: String
    /// SEC's `primaryDocDescription` — a short human-readable title.
    /// Optional so cached data written before this field existed still decodes.
    var title: String?

    /// Comma-separated 8-K item codes (e.g. "2.02,9.01") — SEC's own
    /// subject-matter tags. Empty for non-8-K filings.
    var items: String?

    /// Populated for insider filings (Form 3/4/5/144) once we've fetched
    /// and parsed the filing's XML. Nil for other forms or before the
    /// enrichment fetch completes.
    var insider: InsiderInfo?

    var isInsiderForm: Bool {
        ["3", "4", "5", "144", "3/A", "4/A", "5/A", "144/A"].contains(form)
    }

    /// Human-readable filing description built from:
    ///   1. The standard SEC form description ("Annual Report" for 10-K, etc.),
    ///   2. Any 8-K item subject-matter tags,
    ///   3. `primaryDocDescription` if none of the above applied.
    var displayTitle: String {
        let formDesc = Self.formDescription(for: form)
        let itemDescs = Self.itemDescriptions(from: items ?? "")

        // 8-K with items: "Current Report — Results of Operations, Financial Statements"
        if !itemDescs.isEmpty {
            return "\(formDesc) — \(itemDescs.joined(separator: ", "))"
        }

        if formDesc != form {
            return formDesc
        }

        let trimmed = (title ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare(form) == .orderedSame {
            return form
        }
        return trimmed
    }

    // MARK: - Form + item lookup tables

    private static func formDescription(for form: String) -> String {
        // Strip any "/A" (amendment) suffix so 10-K/A → 10-K lookup.
        let base = form.replacingOccurrences(of: "/A", with: "")
        let isAmendment = form.hasSuffix("/A")
        let title = formTable[base] ?? form
        return isAmendment && title != form ? "\(title) (Amendment)" : title
    }

    private static let formTable: [String: String] = [
        "10-K":     "Annual Report",
        "10-Q":     "Quarterly Report",
        "8-K":      "Current Report",
        "6-K":      "Foreign Issuer Report",
        "20-F":     "Foreign Issuer Annual Report",
        "40-F":     "Canadian Issuer Annual Report",
        "S-1":      "Registration Statement (IPO)",
        "S-3":      "Registration Statement (Shelf)",
        "S-4":      "Registration Statement (M&A)",
        "S-8":      "Registration Statement (Employee Benefit)",
        "F-1":      "Foreign Registration Statement (IPO)",
        "F-3":      "Foreign Registration Statement (Shelf)",
        "424B1":    "Prospectus (Rule 424(b)(1))",
        "424B2":    "Prospectus (Rule 424(b)(2))",
        "424B3":    "Prospectus (Rule 424(b)(3))",
        "424B4":    "Prospectus (Rule 424(b)(4))",
        "424B5":    "Prospectus (Rule 424(b)(5))",
        "3":        "Initial Insider Beneficial Ownership",
        "4":        "Insider Trading Statement",
        "5":        "Annual Insider Beneficial Ownership",
        "144":      "Notice of Proposed Sale of Securities",
        "SC 13D":   "Beneficial Ownership (Active)",
        "SC 13G":   "Beneficial Ownership (Passive)",
        "13F-HR":   "Institutional Holdings Report",
        "13F-NT":   "Institutional Holdings Notice",
        "DEF 14A":  "Definitive Proxy Statement",
        "PRE 14A":  "Preliminary Proxy Statement",
        "DEFA14A":  "Additional Proxy Materials",
        "N-CSR":    "Certified Fund Shareholder Report",
        "N-Q":      "Fund Quarterly Portfolio Holdings",
        "N-PX":     "Fund Proxy Voting Record",
        "EFFECT":   "Notice of Effectiveness",
        "NT 10-K":  "Notification of Late 10-K Filing",
        "NT 10-Q":  "Notification of Late 10-Q Filing",
        "CORRESP":  "Correspondence to SEC",
        "UPLOAD":   "SEC Comment Letter",
    ]

    /// Parse the raw items string ("2.02,9.01") into human-readable subject
    /// descriptions. Unknown codes are dropped rather than shown verbatim.
    private static func itemDescriptions(from raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        let codes = raw
            .split(whereSeparator: { ",;\n\r ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return codes.compactMap { itemTable[$0] }
    }

    // MARK: - Insider-filing companion types

    /// Parsed contents of a Form 3/4/5/144 XML — attached to a `FilingItem`
    /// after the enrichment fetch resolves.
    struct InsiderInfo: Codable, Equatable {
        let ownerName: String
        let ownerCIK: String
        let relationships: [String]   // "Director", "Officer — CEO", "10%+ Owner"
        let periodOfReport: String
        let transactions: [InsiderTransaction]

        /// Compact one-liner for lists / notifications.
        var summaryLine: String {
            if transactions.isEmpty {
                return relationships.joined(separator: ", ")
            }
            let first = transactions[0]
            let base = first.compactSummary
            return transactions.count == 1 ? base : "\(base)  · +\(transactions.count - 1) more"
        }
    }

    struct InsiderTransaction: Codable, Equatable {
        let securityTitle: String
        let date: String
        /// One-letter SEC transaction code: P/S/A/M/F/G/X/D/…
        let code: String
        /// "A" = acquired / "D" = disposed
        let acquiredDisposed: String
        let shares: String
        /// nil for grants / non-priced trades
        let price: String?
        let sharesHeldAfter: String
        /// "D" = direct, "I" = indirect (e.g. by trust/spouse)
        let directOrIndirect: String
        let ownershipNature: String?
        /// True for derivative (options) transactions vs plain stock.
        let isDerivative: Bool

        /// e.g. "Sold 7,801 sh @ $13.74"
        var compactSummary: String {
            let verb = Self.verbForCode(code, acquired: acquiredDisposed)
            let sharesFmt = Self.formatShares(shares)
            var out = "\(verb) \(sharesFmt) sh"
            if let p = price, !p.isEmpty, p != "0", p != "0.0", p != "0.00" {
                out += " @ $\(p)"
            }
            return out
        }

        static func verbForCode(_ code: String, acquired: String) -> String {
            switch code.uppercased() {
            case "P": return "Bought"
            case "S": return "Sold"
            case "A": return "Award"
            case "M": return "Exercised"
            case "F": return "Withheld for tax"
            case "G": return "Gift"
            case "X": return "In-kind"
            case "D": return "Disposed"
            case "J": return "Other"
            case "V": return "Voluntary"
            case "C": return "Conversion"
            case "E": return "Expired"
            default:
                return acquired.uppercased() == "A" ? "Acquired" : "Disposed"
            }
        }

        static func formatShares(_ raw: String) -> String {
            // Best effort — SEC uses fractional shares sometimes.
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 3
            f.minimumFractionDigits = 0
            if let n = Double(raw), let s = f.string(from: NSNumber(value: n)) { return s }
            return raw
        }
    }

    /// 8-K item codes → short descriptions (per SEC Form 8-K instructions).
    private static let itemTable: [String: String] = [
        "1.01": "Material Definitive Agreement",
        "1.02": "Termination of Material Definitive Agreement",
        "1.03": "Bankruptcy",
        "1.04": "Mine Safety",
        "2.01": "Completion of Acquisition/Disposition",
        "2.02": "Results of Operations",
        "2.03": "Direct Financial Obligation",
        "2.04": "Off-Balance-Sheet Arrangement",
        "2.05": "Costs Associated with Exit",
        "2.06": "Material Impairment",
        "3.01": "Notice of Delisting",
        "3.02": "Unregistered Sales of Equity",
        "3.03": "Material Modification to Securityholder Rights",
        "4.01": "Change in Auditor",
        "4.02": "Non-Reliance on Prior Financials",
        "5.01": "Change in Control",
        "5.02": "Directors/Officers Departure or Election",
        "5.03": "Amendments to Charter/Bylaws",
        "5.04": "Blackout Period Notice",
        "5.05": "Amendment to Code of Ethics",
        "5.06": "Change in Shell Company Status",
        "5.07": "Shareholder Vote Results",
        "5.08": "Shareholder Nominations",
        "6.01": "ABS Informational Materials",
        "6.02": "Change of Servicer/Trustee",
        "6.03": "Change in Credit Enhancement",
        "6.04": "Failure to Make a Required Distribution",
        "6.05": "Securities Act Updating Disclosure",
        "7.01": "Regulation FD Disclosure",
        "8.01": "Other Events",
        "9.01": "Financial Statements and Exhibits",
    ]

    /// Deep-link to the primary document on the EDGAR archives:
    /// https://www.sec.gov/Archives/edgar/data/<cikNumeric>/<accessionNoDashes>/<primaryDocument>
    var documentURL: URL? {
        let accNoDashes = accessionNumber.replacingOccurrences(of: "-", with: "")
        let cikNumeric = cik.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        // If CIK is all zeros we'd lose it — fall back to the raw value.
        let numeric = cikNumeric.isEmpty ? cik : cikNumeric
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(numeric)/\(accNoDashes)/\(primaryDocument)")
    }

    /// A short label suitable for lists — e.g. "10-K · 2026-07-05".
    var listLabel: String { "\(form) · \(filingDate)" }
}
