//
//  UpdateItemView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/15/25.
//

import SwiftUI
import SwiftData

//struct FormTopKeyUpdateItem: PreferenceKey {
//    static var defaultValue: CGFloat = 0
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = nextValue()
//    }
//}
struct SearchItemView: View {
    @State private var formTop: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var itemsModel
    @ObservedObject var message = SharedProperties.shared
    
    @State private var searchByDate = true
    @State private var itemName = ""
    @State private var dateFrom = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    @State private var dateTo = Date()
    
    var body: some View {
        ZStack{
            VStack{
                ZeroWasteHeader{dismiss()}
                
                Spacer()
                
                formSection
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
            
            FormAvatarImage(imageName: "Update", formTop: formTop)
            
//            Image("Update")
//                .resizable()
//                .frame(width: 120, height: 120)
//                .clipShape(Circle())
//                .overlay(Circle().stroke(Color.white, lineWidth: 4))
//                .position(x: UIScreen.main.bounds.width / 2, y: formTop + 145)
            
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
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                
                Spacer().frame(height: 20)
                
                Text("Item name")
                    .foregroundColor(.gray)
                
                TextField("Item name", text: $itemName)
                    .padding().frame(height: 40)
                    .font(.system(size: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
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
                    Button("Search") {
                        
                    }
                    .zeroWasteStyle(width: 170)
                    Spacer()
                }
                
                List {
                    
                }
                .listStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .scrollContentBackground(.hidden)
                .padding(.horizontal)
                
            }
        }
    }
}

#Preview {
    SearchItemView()
}
