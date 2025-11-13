//
//  LoginView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/9/25.
//

import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(\.modelContext) var userModel
    @ObservedObject var message = SharedProperties.shared
    @State private var formTop: CGFloat = 0
    @State private var isNavigateToHome = false
    
    enum Field { case username, password }
    @FocusState private var focusedField: Field?
    
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    ZeroWasteHeader { }

                    Spacer()

                    NavigationLink(destination: HomeView(), isActive: $isNavigateToHome) {
                        EmptyView()
                    }.hidden()

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

                FormAvatarImage(imageName: "Login", formTop: formTop)
            }
            .background {
                Image("Background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            .navigationBarBackButtonHidden()
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 30) {
            Spacer().frame(height: 50)

            TextField("Username", text: $username)
                .focused($focusedField, equals: .username)
                .padding()
                .font(.system(size: 20))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray, lineWidth: 2))
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            SecureField("Password", text: $password)
                .focused($focusedField, equals: .password)
                .padding()
                .font(.system(size: 20))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray, lineWidth: 2))
                .submitLabel(.done)
                .onSubmit { login() }

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

            HStack {
                Spacer()
                Button("Login") {
                    login()
                }.zeroWasteStyle(width: 100)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    NavigationLink(destination: RegisterView(isNew: true)
                        .onAppear {message.errorMessage = ""}) {
                            Text("Register")
                        }
                    NavigationLink(destination: RegisterView(isNew: false)
                        .onAppear {message.errorMessage = ""}) {
                            Text("Forgot Password")
                        }
                }
                Spacer()
            }

            Spacer().frame(height: 10)
        }
    }
    
    private func login() {
        focusedField = nil
        Task {
            do {
                let lowerUsername = username.lowercased()
                message.errorMessage = try User.userValidation(
                    isNew: false,
                    username: lowerUsername,
                    password: password,
                    modelContext: userModel)

                if message.errorMessage.isEmpty {
                    if let user = try User.getUserByUsername(lowerUsername, in: userModel),
                       let decrypted = User.decryptPassword(user.password),
                       decrypted == password {
                        let username = user.username
                        let descriptor = FetchDescriptor<Item>(
                            predicate: #Predicate { $0.username == username }
                        )
                        let userItems = try userModel.fetch(descriptor)
                        NotificationManager.shared.rescheduleAll(items: userItems, user: user)
                        UserSession.shared.currentUser = user
                        isNavigateToHome = true
                    } else {
                        message.errorMessage = "Incorrect password"
                    }
                }
            } catch {
                message.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView()
}
