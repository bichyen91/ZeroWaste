//
//  ScanReceiptHelper.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 9/20/25.
//

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ScanReceiptHelper {
    // MARK: - Store detection
    enum StoreKind { case walmart, wholeFoods, tanA, other }

    static func detectStoreKind(lines: [String]) -> StoreKind {
        let joined = lines.joined(separator: " ").lowercased()
        if joined.contains("walmart") { return .walmart }
        if joined.contains("whole foods") || joined.contains("wholefoods") { return .wholeFoods }
        if joined.contains("tan a grocery") || joined.contains("tan a grocery store") { return .tanA }
        return .other
    }

    // Slice lines into the likely item section according to store-specific rules
    static func sliceLinesForItems(lines: [String]) -> [String] {
        let kind = detectStoreKind(lines: lines)
        var start = 0
        var end = lines.count - 1

        switch kind {
        case .wholeFoods:
            // start after address (city, state, zip) – find first line containing pattern like ", ST 12345"
            if let idx = lines.firstIndex(where: { $0.range(of: #",\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil }) {
                start = min(lines.count - 1, idx + 1)
            } else if let anchor = findStartAnchorIndex(in: lines) { start = min(lines.count - 1, anchor + 1) }
            // end at Subtotal (keep date after end for purchase date logic elsewhere)
            if let idx = lines.firstIndex(where: { $0.lowercased().contains("subtotal") }) { end = max(start, idx - 1) }
        case .walmart:
            // Prefer explicit anchors so we do not drop the first item line (happened when the first long-number line was the item barcode).
            if let itemsIdx = lines.firstIndex(where: { $0.lowercased().contains("items sold") }) {
                start = min(lines.count - 1, itemsIdx + 1) // move to the TC#/barcode block
            }
            if let tcIdx = lines.firstIndex(where: { $0.lowercased().contains("tc#") }) {
                start = max(start, min(lines.count - 1, tcIdx + 1))
            }
            // If the next line is a pure barcode (digits only), skip it once to land on the first product line.
            if start < lines.count,
               lines[start].trimmingCharacters(in: .whitespacesAndNewlines)
                    .range(of: #"^\d{10,}$"#, options: .regularExpression) != nil {
                start = min(lines.count - 1, start + 1)
            }
            // Fallback: only if we still have no anchor, look for a long numeric-only line
            if start == 0, let codeIdx = lines.firstIndex(where: { $0.range(of: #"\b\d{10,}\b"#, options: .regularExpression) != nil }) {
                start = min(lines.count - 1, codeIdx + 1)
            }
            if let subIdx = lines.firstIndex(where: { $0.lowercased().contains("subtotal") }) { end = max(start, subIdx - 1) }
        case .tanA:
            if let dIdx = lines.firstIndex(where: { $0.lowercased().contains("description") }) { start = min(lines.count - 1, dIdx + 1) }
            if let subIdx = lines.firstIndex(where: { $0.lowercased().contains("subtotal") }) { end = max(start, subIdx - 1) }
        case .other:
            // start after address or phone
            if let anchor = findStartAnchorIndex(in: lines) { start = min(lines.count - 1, anchor + 1) }
            // end at subtotal/total
            if let countIdx = lines.firstIndex(where: { $0.lowercased().contains("item count") }) { end = max(start, countIdx - 1) }
            else if let subIdx = lines.firstIndex(where: { $0.lowercased().contains("subtotal") }) { end = max(start, subIdx - 1) }
            else if let totIdx = lines.firstIndex(where: { $0.lowercased().contains("total") }) { end = max(start, totIdx - 1) }
        }

        if start > end { return [] }
        return Array(lines[start...end])
    }
    // Common non-item keywords to exclude anywhere in text
    private static let skipKeywords: [String] = [
        "total","sales total","subtotal","tax","change","cash","amount","discount","coupon",
        "fee","tip","payment","card","auth","refund","return","balance","approved",
        "visa","mastercard","amex","debit","tender","credit","cashback","due",
        "qty","oty","price","user","option","station","ticket","description","grocery","store",
        "receipt","order","number","trans","terminal","date","time","tel","phone","address",
        "street","ave","avenue","blvd","boulevard","road","rd","drive",
        "invoice","batch","clerk","cashier","pos","merchant","thank","visit","welcome",
        "container","tare","tare weight","reg","saving","savings", "each",
        "voided"
    ]

    // Extra patterns that require word-boundary matching to avoid over-filtering
    private static let skipRegexes: [String] = [
        #"\brep\b"#,
        #"\bmember(s)?\b"#,
        #"\bcashier\b"#,
        #"\buser\b"#,
        #"\bstation\b"#,
        #"\bbalance\b"#,
        #"\bamount\b"#,
        #"\bvisa\b"#,
        #"\bid\b"#,
        #"\bapproved\b"#,
        #"\bpurchase\b"#,
        #"\bchange\b"#,
        #"\bsavings?\b"#,
        #"(?:wholesale|whosesale)"#,
        #"\bthank(?:\s+you)?\b"#,
        #"\btran\b"#,
        #"\btax(?:es)?\b"#,
        #"\breg\b"#
    ]
    // MARK: - Image Enhance (helps OCR on dim/glare receipts)
    static func enhance(image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let ctx = CIContext()
        let expo = CIFilter.exposureAdjust()
        expo.inputImage = ci
        expo.ev = 0.4
        
        let controls = CIFilter.colorControls()
        controls.inputImage = expo.outputImage
        controls.contrast = 1.15
        controls.brightness = 0.0
        controls.saturation = 0.0 // receipts are mostly grayscale
        
        guard let out = controls.outputImage,
              let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Purchase Date Extraction
    static func extractPurchaseDate(lines: [String], full: String) -> Date? {
        let dateRegexes = datePatterns()
        // Determine first footer marker position (subtotal/total/item count), but avoid header line
        var cutoff = lines.count
        for (i, raw) in lines.enumerated() {
            let lower = raw.lowercased()
            let looksLikeHeader = (lower.contains("qty") && lower.contains("price") && lower.contains("total")) ||
                                   (lower.contains("qty") || lower.contains("price"))
            if lower.contains("subtotal") { cutoff = i; break }
            if lower.contains("item count") { cutoff = i; break }
            if lower.contains("total") && !looksLikeHeader { cutoff = i; break }
        }
        let before = Array(lines.prefix(cutoff)).joined(separator: " ")
        let after = Array(lines.suffix(max(0, lines.count - cutoff))).joined(separator: " ")
        // 1) Prefer a date found before the footer
        if let s = firstRegexMatch(in: before, patterns: dateRegexes), let d = parseAnyDate(s) {
            return d
        }
        // 2) Otherwise, accept a date after the footer
        if let s = firstRegexMatch(in: after, patterns: dateRegexes), let d = parseAnyDate(s) {
            return d
        }
        // 3) Fallback: scan full text
        if let s = firstRegexMatch(in: full, patterns: dateRegexes), let d = parseAnyDate(s) {
            return d
        }
        return nil
    }
    
    private static func datePatterns() -> [String] {
        return [
            #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,      // 7/27/25 or 7/27/2025
            #"\b\d{1,2}-\d{1,2}-\d{2,4}\b"#,      // 7-27-25 or 7-27-2025
            #"\b\d{2}/\d{2}/\d{4}\b"#,            // 07/27/2025
            #"\b\d{4}-\d{2}-\d{2}\b"#,            // 2025-09-25
            #"\b\d{1,2}\s+\w{3}\s+\d{4}\b"#,      // 25 Sep 2025
            #"\b\w{3}\s+\d{1,2},?\s+\d{4}\b"#     // Sep 25, 2025
        ]
    }
    
    private static func firstRegexMatch(in text: String, patterns: [String]) -> String? {
        for p in patterns {
            if let r = text.range(of: p, options: .regularExpression) {
                return String(text[r])
            }
        }
        return nil
    }

    // Find the index of the first line that looks like an address/phone/website or the description header.
    // We will start item extraction AFTER this line so we skip store headers while allowing dates before this area.
    static func findStartAnchorIndex(in lines: [String]) -> Int? {
        let urlRegex = #"https?://|www\."#
        let phoneRegex1 = #"\(\d{3}\)\s*\d{3}-\d{4}"#
        let phoneRegex2 = #"\b\d{3}[-\s]\d{3}[-\s]\d{4}\b"#
        // Require a typical address line like "City, ST 12345"
        let zipRegex = #",\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?\b"#
        for (i, raw) in lines.enumerated() {
            let lower = raw.lowercased()
            if lower.contains("description") { return i }
            if raw.range(of: urlRegex, options: .regularExpression) != nil { return i }
            if raw.range(of: phoneRegex1, options: .regularExpression) != nil { return i }
            if raw.range(of: phoneRegex2, options: .regularExpression) != nil { return i }
            if raw.range(of: zipRegex, options: .regularExpression) != nil { return i }
            // Basic street indicators: contains a number and a street token
            if raw.range(of: #"\b\d+\b"#, options: .regularExpression) != nil {
                let hasStreetToken = ["street","ave","avenue","blvd","boulevard","road","rd","drive"].contains { lower.contains($0) }
                if hasStreetToken { return i }
            }
        }
        return nil
    }
    
    static func parseAnyDate(_ s: String) -> Date? {
        if let d = SharedProperties.parseStringToDate(from: s, to: "yyyy-MM-dd") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "MM/dd/yyyy") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "M/d/yyyy") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "MM-dd-yyyy") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "dd MMM yyyy") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "MMM dd, yyyy") { return d }
        if let d = SharedProperties.parseStringToDate(from: s, to: "MMM dd yyyy") { return d }
        
        let slashed = s.replacingOccurrences(of: "-", with: "/")
        let comps = slashed.split(separator: "/")
        if comps.count == 3, comps[2].count == 2, let yy = Int(comps[2]) {
            let year = 2000 + yy
            let month = comps[0].count == 1 ? "0\(comps[0])" : String(comps[0])
            let day = comps[1].count == 1 ? "0\(comps[1])" : String(comps[1])
            let iso = "\(year)-\(month)-\(day)"
            return SharedProperties.parseStringToDate(from: iso, to: "yyyy-MM-dd")
        }
        return nil
    }
    
    static func normalizeToLocalMidday(_ date: Date) -> Date {
        // The parsed date is created at 00:00 in UTC (see SharedProperties.parseStringToDate).
        // Extract the calendar day in UTC, then create a local-time date at 12:00 to avoid day shifts.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utcCal.dateComponents([.year, .month, .day], from: date)
        var localCal = Calendar.current
        localCal.timeZone = TimeZone.current
        return localCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) ?? date
    }

    // MARK: - Line-by-line item extraction (letters-only)
    // Return non-empty lines in order with ONLY alphabet letters and words (>=2 chars).
    static func extractItemsLineByLine(lines: [String]) -> [String] {
        // Use store-aware slicing rules first
        let slice = sliceLinesForItems(lines: lines)
        return slice.enumerated().compactMap { (_, raw) in
            let lower = raw.lowercased()
            if containsSkipKeyword(in: lower) { return nil }
            if raw.contains("#") { return nil }
            // phone number formats
            if raw.range(of: #"\(\d{3}\)\s*\d{3}-\d{4}"#, options: .regularExpression) != nil { return nil }
            if raw.range(of: #"\b\d{3}[-\s]\d{3}[-\s]\d{4}\b"#, options: .regularExpression) != nil { return nil }
        // Address lines (City, ST ZIP). Do not filter lines that only contain 5-digit numbers (item codes)
        let cityStateZip = #"[A-Za-z][A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?\b"#
        if raw.range(of: cityStateZip, options: .regularExpression) != nil { return nil }
            // keep only letters and multi-char words
            let letters = lettersOnlyWords(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if letters.isEmpty { return nil }
            return letters
        }
    }

    // Keep only alphabetic letters and spaces; drop digits/symbols; remove <=2-letter words
    private static func lettersOnlyWords(_ s: String) -> String {
        if s.isEmpty { return s }
        let kept = s.unicodeScalars.map { scalar -> Character? in
            if CharacterSet.letters.contains(scalar) { return Character(UnicodeScalar(scalar)) }
            if CharacterSet.whitespaces.contains(scalar) { return " " }
            return nil
        }
        var result = String(kept.compactMap { $0 })
        // collapse multiple spaces
        if let regex = try? NSRegularExpression(pattern: "\\s{2,}", options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        // remove <=2-letter words and common unit tokens
        let tokens = result.split(separator: " ")
        let bannedUnits: Set<String> = ["lb","oz","kg","g","ea","ct","pk"]
        let filtered = tokens.compactMap { tok -> String? in
            let t = String(tok)
            if t.count <= 2 { return nil }
            if bannedUnits.contains(t.lowercased()) { return nil }
            return t
        }
        return filtered.joined(separator: " ")
    }
    
    private static func containsSkipKeyword(in text: String) -> Bool {
        if skipKeywords.contains(where: { text.contains($0) }) { return true }
        for regex in skipRegexes {
            if text.range(of: regex, options: .regularExpression) != nil { return true }
        }
        return false
    }
    
    private static func cleanItemName(_ s: String) -> String {
        var name = s
        name = name.replacingOccurrences(of: #"^\s*\d+\s*[xX]?\s+"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^\(.*?\)\s*"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*@\s*\$?\d+(?:[.,]\d{2})?.*$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s+\d+\s*@\s*\$?\d+(?:[.,]\d{2}).*$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*\d+\.?\d*\s*(lb|oz|kg|g|ea|each|ct|pk)\s*$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func isAllowedItemName(_ s: String) -> Bool {
        if s.isEmpty { return false }
        let lower = s.lowercased()
        let banned = ["total","tax","subtotal","change","cash","amount","discount",
                      "coupon","fee","tip","payment","card","auth","refund","return","tender"]
        if banned.contains(where: { lower.contains($0) }) { return false }
        return s.count >= 3 && s.count <= 60
    }
    
    // MARK: - OCR normalization helpers
    static func normalizeOCRGlitches(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"(?<=\b[A-Z])0(?=[A-Z]+\b)"#, with: "O", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\b[0-9])O(?=[0-9]+\b)"#, with: "0", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\b)I(?=\d+\b)"#, with: "1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\b)\l(?=\d+\b)"#, with: "1", options: .regularExpression)
        // fix spaced decimals like "49. 79" or "$4 , 19" → "49.79" / "$4.19"
        t = t.replacingOccurrences(of: #"(\d)\s*[\.,]\s*(\d{2})"#, with: "$1.$2", options: .regularExpression)
        // collapse multiple spaces
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t
    }
}
