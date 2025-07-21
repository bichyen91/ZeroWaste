//
//  User.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/18/25.
//

import Foundation
import SwiftData
import CryptoKit

@Model
class User {
    
    static let requiredLength = 6
    
    static let encryptionKey: SymmetricKey = {
        if let keyData = UserDefaults.standard.data(forKey: "encryptionKey") {
            return SymmetricKey(data: keyData)
        } else {
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            UserDefaults.standard.set(keyData, forKey: "encryptionKey")
            return key
        }
    }()
    
    @Attribute var username: String
    @Attribute var password: String
    @Attribute var alert_day: Int
    @Attribute var alert_time: String
    
    init(username: String = "",
         password: String = "",
         alert_day: Int = 3,
         alert_time: String = "08:00") {
        self.username = username
        self.password = password
        self.alert_day = alert_day
        self.alert_time = alert_time
    }
    
    static func getUserByUsername(_ username: String, in context: ModelContext) throws -> User? {
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.username == username }
        )
        descriptor.fetchLimit = 1
        let users = try context.fetch(descriptor)
        return users.first
    }
    
    static func encryptPassword(_ decrypted: String) throws -> String {
        let data = decrypted.data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined!.base64EncodedString()
    }
    
    static func decryptPassword(_ encrypted: String) -> String?{
        guard let data = Data(base64Encoded: encrypted),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decryptData = try? AES.GCM.open(sealedBox, using: encryptionKey)else {
            return nil
        }
        return String(data: decryptData, encoding: .utf8)
    }
    
    static func userValidation(isNew: Bool, username: String, password: String, modelContext: ModelContext) throws -> String{
        guard !username.isEmpty && !password.isEmpty else{
            return "Username and password are required"
        }
        if isNew { //new register
            if let _ = try getUserByUsername(username, in: modelContext){
                return "Username already exists"
            }
        }
        else { //update password
            if try getUserByUsername(username, in: modelContext) == nil {
                return "User does not exist"
            }
        }
        guard password.count >= requiredLength else {
            return "Password must be at least \(requiredLength) charactors long"
        }
        return ""
    }
}
