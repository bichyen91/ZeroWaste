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
    @State private var formTop: CGFloat = 0
    @State private var refreshID = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var itemModel
    
    var body: some View {
        let nonExpiredSorted = Item.getNonExpiredItems(items, isRemovedMode: true)
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
                        
                        Spacer().frame(height: 40)
                        
                        HStack{
                            List {
                                if !nonExpiredSorted.isEmpty {
                                    ForEach(nonExpiredSorted, id: \.itemCode) { item in
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
                                                do {
                                                    itemModel.delete(item)
                                                    try itemModel.save()
                                                    refreshID = UUID()
                                                } catch {
                                                    print(error)
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    HStack {
                                        Spacer()
                                        Text("List is empty")
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

//    struct RoundedCorner: Shape {
//        var radius: CGFloat = 20.0
//        var corners: UIRectCorner = .allCorners
//
//        func path(in rect: CGRect) -> Path {
//            let path = UIBezierPath(
//                roundedRect: rect,
//                byRoundingCorners: corners,
//                cornerRadii: CGSize(width: radius, height: radius)
//            )
//            return Path(path.cgPath)
//        }
//    }
}


#Preview {
    RemoveItemsView()
        .modelContainer(for: Item.self, inMemory: true)
}
