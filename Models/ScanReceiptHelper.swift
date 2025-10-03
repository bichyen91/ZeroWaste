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
        let keyWords = ["purchase", "purchased", "date", "datetime", "receipt", "txn", "order", "time"]
        let dateRegexes = datePatterns()
        
        for (i, raw) in lines.enumerated() {
            let l = raw.lowercased()
            guard keyWords.contains(where: { l.contains($0) }) else { continue }
            let window = Array(lines[max(0, i-1)...min(lines.count-1, i+2)]).joined(separator: " ")
            if let s = firstRegexMatch(in: window, patterns: dateRegexes),
               let d = parseAnyDate(s) {
                return d
            }
        }
        if let s = firstRegexMatch(in: full, patterns: dateRegexes),
           let d = parseAnyDate(s) {
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
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let components = cal.dateComponents([.year, .month, .day], from: date)
        return cal.date(from: DateComponents(year: components.year, month: components.month, day: components.day, hour: 12)) ?? date
    }
    
    // MARK: - Item Section Heuristics
    static func findItemSection(in lines: [String]) -> (start: Int, end: Int) {
        var start = 0
        var end = lines.count - 1
        
        for (i, line) in lines.enumerated() {
            if isItemLine(line) { start = i; break }
        }
        for (i, line) in lines.enumerated() {
            let l = line.lowercased()
            if l.contains("subtotal") || l.contains("tax") || l.contains("total") ||
                l.contains("tender") || l.contains("change") || l.contains("visa") ||
                l.contains("mastercard") || l.contains("debit") || l.contains("cash") ||
                l.contains("payment") || l.contains("amount due") {
                end = max(start, i - 1); break
            }
        }
        return (max(0, start), min(lines.count - 1, end))
    }
    
    private static func isItemLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.range(of: #"(?:\$)?\d{1,4}(?:[.,]\d{2})$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^\d+\s+"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"\s[xX]\s*\d+"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"\s@\s*\$?\d"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"\d+\.?\d*\s*(lb|oz|kg|g|ea|each|ct|pk)"#, options: .regularExpression) != nil { return true }
        return false
    }
    
    // MARK: - Item Extraction (name only)
    static func extractItemsFromSection(lines: [String], startIndex: Int, endIndex: Int) -> [String] {
        var items: [String] = []
        if lines.isEmpty { return items }
        let section = Array(lines[startIndex...endIndex])
        
        items.append(contentsOf: extractInlinePriceItems(from: section))
        items.append(contentsOf: extractPriceOnlyItems(from: section))
        items.append(contentsOf: extractMultiLineItems(from: section))
        
        let cleaned = items
            .map { cleanItemName($0) }
            .filter { isAllowedItemName($0) }
        
        var seen = Set<String>()
        var result: [String] = []
        for s in cleaned {
            let key = s.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(s)
            }
        }
        return result
    }

    // MARK: - Line-by-line item extraction (no filtering)
    // Return all non-empty lines in order, as-is (after upstream normalization).
    static func extractItemsLineByLine(lines: [String]) -> [String] {
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private static func extractInlinePriceItems(from lines: [String]) -> [String] {
        var items: [String] = []
        let priceRegex = #"(?:\$)?\d{1,4}(?:[.,]\d{2})\s*$"#
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = t.range(of: priceRegex, options: .regularExpression) {
                let left = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                if isItemNameCandidate(left) { items.append(left) }
            }
        }
        return items
    }
    
    private static func extractPriceOnlyItems(from lines: [String]) -> [String] {
        var items: [String] = []
        let priceOnly = #"^\s*(?:\$)?\d{1,4}(?:[.,]\d{2})\s*$"#
        for (i, raw) in lines.enumerated() {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.range(of: priceOnly, options: .regularExpression) != nil else { continue }
            let lo = max(0, i-2), hi = max(0, i-1)
            for j in stride(from: hi, through: lo, by: -1) {
                let cand = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if isItemNameCandidate(cand) { items.append(cand); break }
            }
        }
        return items
    }
    
    private static func extractMultiLineItems(from lines: [String]) -> [String] {
        var items: [String] = []
        let priceRegex = #"(?:\$)?\d{1,4}(?:[.,]\d{2})\s*$"#
        for i in 0..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.range(of: priceRegex, options: .regularExpression) != nil else { continue }
            for j in stride(from: max(0, i-3), through: max(0, i-1), by: -1) {
                let cand = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if isItemNameCandidate(cand) { items.append(cand); break }
            }
        }
        return items
    }
    
    private static func isItemNameCandidate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let lower = trimmed.lowercased()
        let skipWords = [
            "total","sales total","subtotal","tax","change","cash","amount","discount","coupon",
            "fee","tip","payment","card","auth","refund","return","balance","approved","appr",
            "visa","mastercard","amex","debit","tender","credit","cashback","due",
            // headers and non-item context
            "qty","price","qty price","user","option","station","ticket","description",
            "grocery","store","visa"
        ]
        if skipWords.contains(where: { lower.contains($0) }) { return false }
        // obvious labels with colon
        if lower.contains("user:") || lower.contains("station:") || lower.contains("tender:") || lower.contains("description:") { return false }
        // phone numbers
        if trimmed.range(of: #"\(\d{3}\)\s*\d{3}-\d{4}"#, options: .regularExpression) != nil { return false }
        if trimmed.range(of: #"\b\d{3}[-\s]\d{3}[-\s]\d{4}\b"#, options: .regularExpression) != nil { return false }
        // address-like patterns City, ST 12345
        if trimmed.range(of: #",\s*[A-Z]{2}\s*\d{5}\b"#, options: .regularExpression) != nil { return false }
        if trimmed.range(of: #"\b\d{4,8}\b"#, options: .regularExpression) != nil,
           trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) == nil { return false }
        let letters = trimmed.filter { $0.isLetter }.count
        if letters < 2 { return false }
        let ratio = Double(letters) / Double(max(1, trimmed.count))
        if ratio < 0.30 { return false }
        return true
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


