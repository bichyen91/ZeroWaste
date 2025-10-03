//
//  InputItemView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/15/25.
//

import SwiftUI
import SwiftData

struct ItemDetailView: View {
    var isNew: Bool
    var selectedItem: Item?
    var onSave: (() -> Void)? = nil

    @State private var formTop: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var itemsModel
    @ObservedObject var message = SharedProperties.shared
    
    @State private var debounceTimer: Timer? = nil
    @State private var isResetForm = false

    @State private var itemCode: String = ""
    @State private var itemName: String = ""
    @State private var purchaseDate = Date()
    @State private var expiredDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
    @State private var username = UserSession.shared.currentUser?.username
    
    init(isNew: Bool = true, selectedItem: Item? = nil, onSave: (() -> Void)? = nil) {
        self.isNew = isNew
        self.selectedItem = selectedItem
        _itemCode = State(initialValue: selectedItem?.itemCode ?? "")
        _itemName = State(initialValue: selectedItem?.itemName.capitalized ?? "")
        _purchaseDate = State(initialValue: selectedItem?.purchasedDate != nil ?
                              SharedProperties.parseStringToDate(from: selectedItem!.purchasedDate, to: "yyyy-MM-dd") ?? Date() : Date())
        _expiredDate = State(initialValue: selectedItem?.expiredDate != nil ?
                             SharedProperties.parseStringToDate(from: selectedItem!.expiredDate, to: "yyyy-MM-dd") ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)!
                             : Calendar.current.date(byAdding: .day, value: 7, to: .now)!)
    }
    
    var body: some View {
        ZStack{
            VStack{
                ZeroWasteHeader { dismiss() }
                
                Spacer()
                
                Group {
                    if isResetForm {
                        formSection
                    } else {
                        formSection
                    }
                }
                .padding()
                .background(
                    GeometryReader { geo in
                        Color.white
                            .preference(key: FormTopKey.self, value: geo.frame(in: .global).minY)
                    }
                )
                .cornerRadius(20)
                .shadow(radius: 20)
                .onPreferenceChange(FormTopKey.self) { value in
                    self.formTop = value
                }
                .padding()

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            FormAvatarImage(imageName: "input", formTop: formTop)
        }
        .background(content: {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        })
        .navigationBarBackButtonHidden()
    }
    
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            
            Spacer().frame(height: 60)
            
            Text("Item name")
                .foregroundColor(.gray)
            
            TextField("Item name", text: $itemName)
                .padding()
                .font(.system(size: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.gray, lineWidth: 2)
                }
                .onChange(of: itemName) { newName in
                    debounceTimer?.invalidate() // Cancel previous timer if it exists
                    
                    if !newName.isEmpty {
                        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                            AIService.shared.predictExpiredDate(itemName: newName, purchaseDate: purchaseDate) { predictedDate in
                                if let date = predictedDate {
                                    expiredDate = date
                                }
                            }
                        }
                    }
                }
            
            HStack{
                Text("Purchase date")
                    .foregroundColor(.gray)
                Spacer()
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.automatic)
                    .labelsHidden()
                    .onChange(of: purchaseDate) { newDate in
                        if !itemName.isEmpty {
                            AIService.shared.predictExpiredDate(itemName: itemName, purchaseDate: newDate) { predictedDate in
                                if let date = predictedDate {
                                    expiredDate = date
                                }
                            }
                        }
                    }
                
            }
            
            HStack{
                Text("Expired date")
                    .foregroundColor(.gray)
                Spacer()
                DatePicker("", selection: $expiredDate, displayedComponents: .date)
                    .datePickerStyle(.automatic)
                    .labelsHidden()
            }
            
            Spacer()
            
            if !message.errorMessage.isEmpty {
                HStack {
                    Spacer()
                    Text(message.errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
            
            buttonsView
            
            Spacer().frame(height: 10)
        }
    }
    
    private var buttonsView: some View {
        HStack{
            Spacer()
            
            Button("Save") {
                Task {
                    do{
                        let lowerItemName = itemName.lowercased()
                        message.errorMessage = Item.itemValidation(itemName: lowerItemName, purchaseDate: purchaseDate, expiredDate: expiredDate, itemsModel: itemsModel, isNew: isNew)
                        
                        if message.errorMessage.isEmpty {
                            if isNew {
                                let newItem = try Item(
                                    itemCode: Item.getNextItemCode(from: itemsModel),
                                    itemName: lowerItemName,
                                    purchasedDate: SharedProperties.parseDateToString(purchaseDate, to: "yyyy-MM-dd"),
                                    expiredDate: SharedProperties.parseDateToString(expiredDate, to: "yyyy-MM-dd"),
                                    createdDate: SharedProperties.parseDateToString(.now, to: "yyyy-MM-dd HH:mm"),
                                    username: UserSession.shared.currentUser!.username)
                                
                                itemsModel.insert(newItem)
                            }
                            else if let updateItem = selectedItem {
                                updateItem.itemName = lowerItemName
                                updateItem.purchasedDate = SharedProperties.parseDateToString(purchaseDate, to: "yyyy-MM-dd")
                                updateItem.expiredDate = SharedProperties.parseDateToString(expiredDate, to: "yyyy-MM-dd")
                            }
                            
                            try itemsModel.save()
                            message.errorMessage = isNew ? "Item added successfully!!!" : "Item updated successfully!!!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                message.errorMessage = ""
                                if isNew {
                                    resetForm()
                                }
                                else {
                                    onSave?()
                                    dismiss()
                                }
                            }
                        }
                        else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                message.errorMessage = ""
                            }
                        }
                    }
                }
            }
            .zeroWasteStyle()
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .zeroWasteStyle()
            
            Spacer()
        }
    }
    
    private func resetForm() {
        isResetForm.toggle()
        itemCode = ""
        itemName = ""
        purchaseDate = Date()
        expiredDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
    }
}

#Preview {
    ItemDetailView(isNew: true)
        .modelContainer(for: Item.self, inMemory: true)
}
