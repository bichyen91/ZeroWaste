//
//  UpdateItemView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/15/25.
//

import SwiftUI
import SwiftData

struct SearchItemView: View {
    @Binding var refreshID: UUID
    @State private var formTop: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var itemsModel
    @ObservedObject var message = SharedProperties.shared
    
    @State private var hasSearched = false
    @State private var selectedItem: Item? = nil
    @State private var itemsSearch: [Item] = []
    @State private var searchByDate = true
    @State private var itemName = ""
    @State private var dateFrom = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    @State private var dateTo = Date()
    
    var body: some View {
        ZStack{
            VStack(spacing: 0){
                ZeroWasteHeader{ dismiss() }
                
                Spacer()
                
                formSection
                    .padding()
                    .background(
                        GeometryReader { geo in
                            Color.white
                                .preference(key: FormTopKey.self, value: geo.frame(in: .global).minY)
                        }
                    )
                    .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
                    .shadow(radius: 20)
                    .onPreferenceChange(FormTopKey.self) { value in
                        self.formTop = value
                    }
                    .padding(.top)
                
                ZStack {
                    RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight])
                        .fill(Color.white)
                    
                    List {
                        if !hasSearched || (itemName == "" && !searchByDate) {
                            HStack {
                                Spacer()
                                Text("Input search criteria... ")
                                    .transition(.opacity.combined(with: .slide))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        }
                        else if itemsSearch.isEmpty {
                            HStack {
                                Spacer()
                                Text("No Item found... ")
                                    .transition(.opacity.combined(with: .slide))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        }
                        else {
                            ForEach(itemsSearch, id: \.itemCode) { item in
                                NavigationLink(
                                    destination: ItemDetailView(isNew: false, selectedItem: item) {
                                        refreshID = UUID()
                                        selectedItem = nil
                                    }
                                ){
                                    VStack(alignment: .leading) {
                                        Text(item.itemName.capitalized)
                                        Text("Purchased: \(item.purchasedDate)\nExpires: \(item.expiredDate)")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedItem = item
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            FormAvatarImage(imageName: "Update", formTop: formTop)
        }
        .background(content: {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        })
        .navigationBarBackButtonHidden()
        .navigationDestination(item: $selectedItem) { item in
            ItemDetailView(isNew: false, selectedItem: item) {
                refreshID = UUID()
                selectedItem = nil
            }
        }
    }
    
    private var formSection: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                
                Spacer().frame(height: 20)
                
                Text("Item name")
                    .foregroundColor(.gray)
                
                TextField("Item name", text: $itemName)
                    .submitLabel(.search)
                    .onSubmit { performSearch() }
                    .padding().frame(height: 40)
                    .font(.system(size: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 2)
                    }
                
                HStack{
                    Text("Purchase date")
                        .foregroundColor(.gray)
                    Spacer()
                    Toggle("", isOn: $searchByDate)
                        .labelsHidden()
                }
                HStack{
                    DatePicker("", selection: $dateFrom, displayedComponents: .date)
                        .datePickerStyle(.automatic)
                        .labelsHidden()
                        .disabled(!searchByDate)
                    Spacer()
                    Text("~")
                    Spacer()
                    DatePicker("", selection: $dateTo, displayedComponents: .date)
                        .datePickerStyle(.automatic)
                        .labelsHidden()
                        .disabled(!searchByDate)
                }
                
                HStack{
                    Spacer()
                    Button("Search") { performSearch() }
                    .zeroWasteStyle(width: 170)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Search actions
extension SearchItemView {
    fileprivate func performSearch() {
        hasSearched = true
        // Ensure UI updates happen on main queue (defensive for real device behavior)
        DispatchQueue.main.async {
            if !itemName.isEmpty && !searchByDate {
                itemsSearch = Item.getItemsByName(from: itemsModel, searchName: itemName)
            }
            else if itemName.isEmpty && searchByDate {
                itemsSearch = Item.getItemsByDate(from: itemsModel, dateFrom: dateFrom, dateTo: dateTo)
            }
            else if !itemName.isEmpty && searchByDate {
                itemsSearch = Item.getItemsByNameAndDateRange(from: itemsModel, searchName: itemName, dateFrom: dateFrom, dateTo: dateTo)
            } else {
                itemsSearch = []
            }
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = 20.0
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension Item: Identifiable {
    var id: String { itemCode }
}

#Preview {
    SearchItemView(refreshID: .constant(UUID()))
}
