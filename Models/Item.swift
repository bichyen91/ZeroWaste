//
//  Items.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/1/25.
//

import Foundation
import SwiftData

@Model
class Item {
    @Attribute var itemCode: String
    @Attribute var itemName: String
    @Attribute var purchasedDate: String
    @Attribute var expiredDate: String
    @Attribute var createdDate: String
    @Attribute var username: String
    
    init(itemCode: String = "",
         itemName: String = "",
         purchasedDate: String = "",
         expiredDate: String = "",
         createdDate: String = "",
         username: String = "")
    {
        self.itemCode = itemCode
        self.itemName = itemName
        self.purchasedDate = purchasedDate
        self.expiredDate = expiredDate
        self.createdDate = createdDate
        self.username = username
    }
    
    static func getNextItemCode(from itemsModel: ModelContext) -> String {
        let data = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.itemCode, order: .forward)])
        if let items = try? itemsModel.fetch(data),
           let lastItem = items.last,
           let lastCode = Int(lastItem.itemCode){
            return String (lastCode + 1)
        }
        return "1"
    }
    
    static func itemValidation(itemName: String) -> String {
        guard !itemName.isEmpty else {
            return "Item name is required"
        }
        return ""
    }
    
    static func getNonExpiredItems(_ items: [Item], dateFormat: String = "yyyy-MM-dd") -> [Item] {
        let today = Date()
        return items.filter { item in
            guard let date = SharedProperties.parseStringToDate(from: item.expiredDate, to: dateFormat) else {
                return false
            }
            return date >= today
        }
    }
}
