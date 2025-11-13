//
//  RemoveItemsView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/16/25.
//

import SwiftUI
import SwiftData

//struct FormTopKeyRemoveItems: PreferenceKey {
//    static var defaultValue: CGFloat = 0
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = nextValue()
//    }
//}

struct RemoveItemsView: View {
    @Query var items: [Item]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var itemModel
    
    @State private var formTop: CGFloat = 0 // icon position
    @State private var refreshID = UUID()
    
    @State private var isSelecting = false
    @State private var selectedItems: Set<String> = []
    
    var body: some View {
        let username = UserSession.shared.currentUser?.username ?? ""
        let userItems = items.filter { $0.username == username }
        let expiredItems = Item.filterItemsByExpiration(userItems, isExpired: true)
            .sorted {
                (SharedProperties.parseStringToDate(from: $0.expiredDate, to: "yyyy-MM-dd") ?? .distantFuture)
                <
                    (SharedProperties.parseStringToDate(from: $1.expiredDate, to: "yyyy-MM-dd") ?? .distantFuture)
            }
        
        ZStack{
            VStack(spacing: 0){
                ZeroWasteHeader{ dismiss() }
                
                Spacer()
                
                ZStack {
                    VStack(alignment: .leading, spacing: 10) {
                        
                        Spacer().frame(height: 10)
                        
                        if !expiredItems.isEmpty {
                            HStack {
                                Button(isSelecting ? "Done" : "Select") {
                                    withAnimation {
                                        isSelecting.toggle()
                                        if !isSelecting {
                                            selectedItems.removeAll()
                                        }
                                    }
                                }
                                .font(.headline)
                                
                                Spacer ()
                                
                                if isSelecting && !selectedItems.isEmpty {
                                    Button ("Delete") { deleteSelectedItems() }.font(.headline)
                                }
                            }
                        }
                        
                        Spacer().frame(height: 10)
                        
                        HStack{
                            List {
                                if !expiredItems.isEmpty {
                                    ForEach(expiredItems, id: \.itemCode) { item in
                                        
                                        if isSelecting {
                                            HStack {
                                                Image(systemName: selectedItems.contains(item.itemCode) ? "checkmark.circle.fill" : "circle")
                                                    .imageScale(.large)
                                                VStack(alignment: .leading) {
                                                    Text(item.itemName.capitalized)
                                                    Text("Purchased: \(item.purchasedDate)\nExpires: \(item.expiredDate)")
                                                        .font(.subheadline)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .onTapGesture {
                                                toggleSelection(for: item.itemCode)
                                            }
                                        }
                                        else {
                                            NavigationLink(destination: ItemDetailView(isNew: false, selectedItem: item){
                                                refreshID = UUID()
                                            }) {
                                                VStack(alignment: .leading) {
                                                    Text(item.itemName.capitalized)
                                                    Text("Purchased: \(item.purchasedDate)\nExpires: \(item.expiredDate)")
                                                        .font(.subheadline)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .swipeActions {
                                                Button("Delete", role: .destructive) {
                                                    deleteItem(item)
                                                }
                                            }
                                            
                                        }
                                    }
                                } else {
                                    HStack {
                                        Spacer()
                                        Text("No expired items")
                                            .foregroundColor(.gray)
                                        Spacer()
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
                .background(
                    GeometryReader { geo in
                        Color.white
                            .preference(key: FormTopKey.self, value: geo.frame(in: .global).minY)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 20)
                .onPreferenceChange(FormTopKey.self) { value in
                    self.formTop = value
                }
                .padding(.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            FormAvatarImage(imageName: "Remove", formTop: formTop)
        }
        .background(content: {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        })
        .navigationBarBackButtonHidden()
    }
    
    private func toggleSelection(for code: String) {
        if selectedItems.contains(code) {
            selectedItems.remove(code)
        }
        else {
            selectedItems.insert(code)
        }
    }
    
    private func deleteItem(_ item: Item) {
        do {
            let code = item.itemCode
            itemModel.delete(item)
            try itemModel.save()
            NotificationManager.shared.cancelForItemCode(code)
            refreshID = UUID()
            selectedItems.remove(item.itemCode)
        }
        catch {
            print("catch error deletion!!!")
        }
    }
    
    private func deleteSelectedItems() {
        do {
            var codesToCancel: [String] = []
            for code in selectedItems {
                if let it = items.first(where: {$0.itemCode == code}) {
                    itemModel.delete(it)
                    codesToCancel.append(code)
                }
            }
            try itemModel.save()
            codesToCancel.forEach { NotificationManager.shared.cancelForItemCode($0) }
            refreshID = UUID()
            selectedItems.removeAll()
        }
        catch {
            print("catch error deletion!!!")
        }
    }
    
}


#Preview {
    RemoveItemsView()
        .modelContainer(for: Item.self, inMemory: true)
}
