//
//  UserSession.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/1/25.
//

import Foundation
import Combine

class UserSession: ObservableObject {
    static let shared = UserSession()

    @Published var currentUser: User? = nil

    private init() {}
    
    func logout() {
        currentUser = nil
    }
}

