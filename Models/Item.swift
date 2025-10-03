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
    
    static func getItemsByName(from itemsModel: ModelContext, searchName: String) -> [Item]{
        // Some SwiftData predicate string methods behave inconsistently on device.
        // Fetch all and filter in memory for reliable results.
        let descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.purchasedDate, order: .forward)]
        )
        do {
            let all = try itemsModel.fetch(descriptor)
            let needle = searchName.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !needle.isEmpty else { return [] }
            return all.filter {
                $0.itemName
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .contains(needle)
            }
        } catch {
            return []
        }
    }
    
    static func getItemsByDate(from itemsModel: ModelContext, dateFrom: Date, dateTo: Date) -> [Item]{
        // Normalize date range to full days in UTC to avoid simulator/device timezone differences
        let utcCalendar = Calendar(identifier: .gregorian)
        var calendar = utcCalendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: dateFrom)
        let endOfDay: Date = {
            if let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dateTo) {
                return end
            }
            return dateTo
        }()
        
        let fetchAllItems = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.purchasedDate, order: .forward)]
        )
        
        do {
            let items = try itemsModel.fetch(fetchAllItems)
            let filterItems = items.filter { item in
                if let parseDate = SharedProperties.parseStringToDate(from: item.purchasedDate, to: "yyyy-MM-dd") {
                    return parseDate >= startOfDay && parseDate <= endOfDay
                }
                return false
            }
            return filterItems
        } catch {
            return []
        }
    }
    
    static func existedItem(from itemsModel: ModelContext, name: String, purchaseDate: Date, dateFormat: String = "yyyy-MM-dd") -> Item? {
        let formattedDate = SharedProperties.parseDateToString(purchaseDate, to: dateFormat)
        let lowerName = name.lowercased()
        
        let fetchDescriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> {
                $0.itemName == lowerName && $0.purchasedDate == formattedDate
            },
            sortBy: [SortDescriptor(\.itemCode, order: .forward)]
        )
        
        do {
            let items = try itemsModel.fetch(fetchDescriptor)
            return items.first
        } catch {
            print("Fetch error: \(error)")
            return nil
        }
    }
    
    static func getItemsByNameAndDateRange(from itemsModel: ModelContext, searchName: String, dateFrom: Date, dateTo: Date) -> [Item]{
        // Normalize date range to full days in UTC to avoid simulator/device timezone differences
        let utcCalendar = Calendar(identifier: .gregorian)
        var calendar = utcCalendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: dateFrom)
        let endOfDay: Date = {
            if let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dateTo) {
                return end
            }
            return dateTo
        }()
        
        let itemByName = getItemsByName(from: itemsModel, searchName: searchName)
        
        let filterItems = itemByName.filter { item in
            if let parseDate = SharedProperties.parseStringToDate(from: item.purchasedDate, to: "yyyy-MM-dd") {
                return parseDate >= startOfDay && parseDate <= endOfDay
            }
            return false
        }
        return filterItems
    }
    
    static func filterItemsByExpiration(_ items: [Item], isExpired: Bool) -> [Item] {
        let today = Date()
        return items.filter { item in
            guard let date = SharedProperties.parseStringToDate(from: item.expiredDate, to: "yyyy-MM-dd") else {
                return false
            }
            return isExpired ? date < today : date >= today
        }
    }
    
    
    static func itemValidation(itemName: String, purchaseDate: Date, expiredDate: Date, itemsModel: ModelContext, isNew: Bool) -> String {
        guard !itemName.isEmpty else {
            return "Item name is required"
        }
        
        guard purchaseDate < expiredDate else {
            return "Invalid Expired date"
        }
        
        if let _ = existedItem(from: itemsModel, name: itemName, purchaseDate: purchaseDate, dateFormat: "yyyy-MM-dd"),
           isNew {
            return "Item already exists"
        }
        
        return ""
    }
}
