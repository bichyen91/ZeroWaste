//
//  RegisterView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/14/25.
//

import SwiftUI
import SwiftData

struct RegisterView: View {
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var userModel
    @ObservedObject var message = SharedProperties.shared
    @State private var formTop: CGFloat = 0
    
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            VStack {
                ZeroWasteHeader { dismiss() }

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

            FormAvatarImage(imageName: isNew ? "Register" : "Usersetting", formTop: formTop)
        }
        .background {
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden()
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Spacer().frame(height: 50)

            Group {
                Text("Username").foregroundColor(.gray)
                TextField("Username", text: $username)
                    .padding()
                    .font(.system(size: 20))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray, lineWidth: 2))

                Text("Password").foregroundColor(.gray)
                SecureField("Password", text: $password)
                    .padding()
                    .font(.system(size: 20))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray, lineWidth: 2))
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
        HStack {
            Spacer()

            if isNew {
                Button("Register") {
                    Task {
                        do {
                            let lowerUsername = username.lowercased()
                            message.errorMessage = try User.userValidation(
                                isNew: isNew,
                                username: lowerUsername,
                                password: password,
                                modelContext: userModel)

                            if message.errorMessage.isEmpty {
                                let encryptedPassword = try User.encryptPassword(password)
                                let newUser = try User(username: lowerUsername, password: encryptedPassword)
                                userModel.insert(newUser)
                                try userModel.save()
                                message.errorMessage = "Registered successfully!!!"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    message.errorMessage = ""
                                    dismiss()
                                }
                            }
                        } catch {
                            message.errorMessage = error.localizedDescription
                        }
                    }
                }.zeroWasteStyle()
            } else {
                Button("Update Password") {
                    Task {
                        do {
                            let lowerUsername = username.lowercased()
                            message.errorMessage = try User.userValidation(
                                isNew: isNew,
                                username: lowerUsername,
                                password: password,
                                modelContext: userModel)

                            if message.errorMessage.isEmpty {
                                if let user = try User.getUserByUsername(lowerUsername, in: userModel) {
                                    user.password = try User.encryptPassword(password)
                                    try userModel.save()
                                    message.errorMessage = "Password updated successfully!"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        message.errorMessage = ""
                                        dismiss()
                                    }
                                }
                            }
                        } catch {
                            message.errorMessage = error.localizedDescription
                        }
                    }
                }.zeroWasteStyle(width: 230)
            }

            Spacer()
        }
    }
}

#Preview {
    RegisterView(isNew: true)
        .modelContainer(for: User.self, inMemory: true)
}

#Preview {
    RegisterView(isNew: false)
        .modelContainer(for: User.self, inMemory: true)
}

