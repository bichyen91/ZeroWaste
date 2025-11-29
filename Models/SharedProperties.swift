//
//  ErrorManager.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/1/25.
//

import Foundation
import SwiftUI

class SharedProperties: ObservableObject {
    static let shared = SharedProperties()
    
    @Published var errorMessage: String = ""
    @Published var isError: Bool = true
    
    private init() {}
    
    static func parseStringToDate(from convertString: String, to formatForm: String) -> Date? {
        let formatter = DateFormatter()
        // Use POSIX locale and a fixed timezone to ensure consistent parsing across Simulator and device
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = formatForm
        return formatter.date(from: convertString)
    }
    
    static func parseDateToString(_ date: Date, to formatForm: String) -> String {
        let formatter = DateFormatter()
        // Use POSIX locale and a fixed timezone to ensure consistent formatting across Simulator and device
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = formatForm
        return formatter.string(from: date)
    }

    // MARK: - Local-time helpers (for time-of-day fields like HH:mm)
    static func parseLocalTime(_ s: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: s)
    }
    
    static func formatLocalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
