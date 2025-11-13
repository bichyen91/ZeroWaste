//
//  HomeView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/15/25.
//

import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Query var items: [Item]
    //    @State private var reloadId = UUID()
    @State private var refreshID = UUID()
    @ObservedObject var message = SharedProperties.shared
    @Environment(\.modelContext) private var itemModel
    @State private var capturedScanImage: UIImage? = nil
    @State private var goToScanReceipt = false
    
    var body: some View {
        NavigationStack {
            let currentUsername = UserSession.shared.currentUser?.username ?? ""
            let userItems = items.filter { $0.username == currentUsername }
            let nonExpiredItems = Item.filterItemsByExpiration(userItems, isExpired: false)
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
                        featureActionButton("Scan", image: "scan") {
                            capturedScanImage = nil
                            goToScanReceipt = true
                        }
                        featureButton("Input", image: "input", destination: ItemDetailView(isNew: true) {
                            refreshID = UUID()
                        })
                        featureButton("Update", image: "Update", destination: SearchItemView(refreshID: $refreshID))
                        featureButton("Remove", image: "Remove", destination: RemoveItemsView())
                    }
                    NavigationLink(destination: ScanReceiptView(initialImage: capturedScanImage), isActive: $goToScanReceipt) {
                        EmptyView()
                    }
                    .hidden()
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer(minLength: 10)
                
                // Scrollable list
                ZStack {
                    RoundedCorner(radius: 20)
                        .fill(Color.white)
                    
                    List {
                        if !nonExpiredItems.isEmpty {
                            ForEach(nonExpiredItems, id: \.itemCode) { item in
                                NavigationLink(destination: ItemDetailView(isNew: false, selectedItem: item){
                                    refreshID = UUID()
                                }) {
                                    VStack(alignment: .leading) {
                                        Text(item.itemName.capitalized)
                                        Text("Purchased: \(localDisplay(from: item.purchasedDate))\nExpires: \(localDisplay(from: item.expiredDate))")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        do {
                                            let code = item.itemCode
                                            itemModel.delete(item)
                                            try itemModel.save()
                                            NotificationManager.shared.cancelForItemCode(code)
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
                }.padding()
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

    private func featureActionButton(_ label: String, image: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
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

// MARK: - Local date display helper
private func localDisplay(from iso: String) -> String {
    guard let parsedUTC = SharedProperties.parseStringToDate(from: iso, to: "yyyy-MM-dd") else {
        return iso
    }
    // Convert parsed UTC date to local calendar day at noon to avoid off-by-one
    var utcCal = Calendar(identifier: .gregorian)
    utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
    let comps = utcCal.dateComponents([.year, .month, .day], from: parsedUTC)
    var localCal = Calendar.current
    localCal.timeZone = TimeZone.current
    let localMidday = localCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) ?? parsedUTC
    
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: localMidday)
}
