//
//  RemoveItemsView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/16/25.
//

import SwiftUI

struct FormTopKeyRemoveItems: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RemoveItemsView: View {
    @State private var formTop: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack{
            VStack{
                HStack{
                    Button {
                        dismiss()
                    } label: {
                        Image("ZeroWasteIconTitle")
                            .resizable()
                            .frame(width: 130, height: 100)
                    }
                    Spacer()
                }
                
                Spacer()
                
                    ZStack {
                        VStack(alignment: .leading, spacing: 10) {
                            
                            Spacer().frame(height: 60)
                            
                            
                            
                            Spacer()
                            
                            HStack{
                                Spacer()
                                Button("Confirm") {
                                    //Register
                                }
                                .frame(width: 120, height: 50)
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                                .background(Color.gray.opacity(0.3))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.black, lineWidth: 1)
                                }
                                Spacer()
                                Button("Cancel") {
                                    //Register
                                }
                                .frame(width: 120, height: 50)
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                                .background(Color.gray.opacity(0.3))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.black, lineWidth: 1)
                                }
                                Spacer()
                            }
                            
                            Spacer().frame(height: 10)
                        }
                    }
                    .padding()
                    .background(
                        GeometryReader { geo in
                            Color.white
                                .preference(key: FormTopKeyRemoveItems.self, value: geo.frame(in: .global).minY)
                        }
                    )
                    .cornerRadius(20)
                    .shadow(radius: 20)
                    .onPreferenceChange(FormTopKeyRemoveItems.self) { value in
                        self.formTop = value
                    }
                    .padding()
                
                    
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
                        
            Image("Remove")
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                .position(x: UIScreen.main.bounds.width / 2, y: formTop + 145)
            
                
        }
        .background(content: {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        })
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    RemoveItemsView()
}
