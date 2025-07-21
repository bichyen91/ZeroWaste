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
    
    private init() {}
    
    static func parseStringToDate(from convertString: String, to formatForm: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = formatForm
        return formatter.date(from: convertString)
    }
    
    static func parseDateToString(_ date: Date, to formatForm: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = formatForm
        return formatter.string(from: date)
    }
}
