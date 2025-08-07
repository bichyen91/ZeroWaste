//
//  HomeView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/15/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query var items: [Item]
    //    @State private var reloadId = UUID()
    @State private var refreshID = UUID()
    @ObservedObject var message = SharedProperties.shared
    @Environment(\.modelContext) private var itemModel
    
    var body: some View {
        NavigationStack {
            let nonExpiredSorted = Item.getNonExpiredItems(items)
                .sorted {
                    (SharedProperties.parseStringToDate(from: $0.expiredDate, to: "yyyy-MM-dd") ?? .distantFuture)
                    <
                        (SharedProperties.parseStringToDate(from: $1.expiredDate, to: "yyyy-MM-dd") ?? .distantFuture)
                }
            
            VStack(spacing: 0) {
                // Header with logo and buttons
                VStack(spacing: 10) {
                    HStack {
                        Button {
                            refreshID = UUID()
                        } label: {
                            Image("ZeroWasteIconTitle")
                                .resizable()
                                .frame(width: 130, height: 100)
                        }
                        Spacer()
                        NavigationLink {
                            UserSettingView()
                        } label: {
                            Image("Usersetting")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray, lineWidth: 3))
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                                )
                        }
                    }
                    
                    HStack(spacing: 15) {
                        featureButton("Scan", image: "scan", destination: EmptyView())
                        featureButton("Input", image: "input", destination: ItemDetailView(isNew: true) {
                            refreshID = UUID()
                        })
                        featureButton("Update", image: "Update", destination: SearchItemView(refreshID: $refreshID))
                        featureButton("Remove", image: "Remove", destination: RemoveItemsView())
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer(minLength: 10)
                
                // Scrollable list
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
            .background(
                Image("Background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
            .navigationBarBackButtonHidden()
            .id(refreshID)
        }
    }
    
    private func featureButton<Destination: View>(_ label: String, image: String, destination: Destination) -> some View {
        VStack(spacing: 10) {
            NavigationLink(destination: destination) {
                Image(image)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray, lineWidth: 3))
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
            }
            Text(label)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Item.self, inMemory: true)
}

