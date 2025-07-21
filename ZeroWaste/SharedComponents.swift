//
//  SharedComponents.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/1/25.
//

import SwiftUI

struct ZeroWasteHeader: View {
    var onBack: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image("ZeroWasteIconTitle")
                    .resizable()
                    .frame(width: 130, height: 100)
            }
            Spacer()
        }
    }
}

struct FormTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FormAvatarImage: View {
    var imageName: String
    var formTop: CGFloat
    
    var body: some View {
        Image(imageName)
            .resizable()
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 4))
            .position(x: UIScreen.main.bounds.width / 2, y: formTop + 145)
    }
}

extension Button {
    func zeroWasteStyle(width: CGFloat = 120) -> some View {
        self.frame(width: width, height: 50)
            .font(.system(size: 24))
            .foregroundColor(.primary)
            .background(Color.gray.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black, lineWidth: 1)
            )
    }
}
