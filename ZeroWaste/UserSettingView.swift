//
//  UserSettingView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/14/25.
//

import SwiftUI
import SwiftData

struct UserSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var userModel
    @ObservedObject var userSession = UserSession.shared
    @ObservedObject var message = SharedProperties.shared
    
    private let minDay = 1
    private let maxDay = 30
    
    @State private var isNavigateToLogin = false
    @State private var formTop: CGFloat = 0
    
    @State private var password = ""
    @State private var alertDay = 3
    @State private var alertTime = Date()
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            VStack {
                ZeroWasteHeader { dismiss() }

                Spacer().frame(height: 20)

                ZStack {
                    VStack(alignment: .leading, spacing: 15) {
                        Spacer().frame(height: 30)

                        Text("Username")
                            .foregroundColor(.gray)
                        TextField("Username", text: .constant(userSession.currentUser?.username ?? ""))
                            .padding()
                            .font(.system(size: 20))
                            .background {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.gray, lineWidth: 2)
                            }
                            .disabled(true)

                        Text("Password")
                            .foregroundColor(.gray)
                        SecureField("Password", text:$password)
                            .padding()
                            .font(.system(size: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.gray, lineWidth: 2)
                            }

                        Text("Alert before items expired \n(Number of days)")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 25) {
                            Button {
                                if alertDay > minDay {
                                    alertDay -= 1
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .padding()
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.3))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray, lineWidth: 2)
                                    }
                            }
                            .disabled(alertDay == minDay)
                            .opacity(alertDay == minDay ? 0.4 : 1.0)

                            Text("\(alertDay)")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .font(.system(size: 20))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.gray, lineWidth: 2)
                                }

                            Button {
                                if alertDay < maxDay {
                                    alertDay += 1
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .padding()
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.3))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray, lineWidth: 2)
                                    }
                            }
                            .disabled(alertDay == maxDay)
                            .opacity(alertDay == maxDay ? 0.4 : 1.0)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack {
                            Text("Alert time")
                                .foregroundColor(.gray)

                            Spacer()

                            DatePicker("", selection: $alertTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.automatic)
                                .frame(width: 120, height: 50)
                                .frame(height: 50)
                                .scaleEffect(1.4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray, lineWidth: 2)
                                )
                                .labelsHidden()
                        }

                        Spacer()

                        NavigationLink(destination: LoginView(), isActive: $isNavigateToLogin) {
                            EmptyView()
                        }.hidden()
                        
                        HStack(spacing: 50) {
                            Button("Save") {
                                guard let user = userSession.currentUser else { return }
                                Task {
                                    do {
                                        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else {
                                            message.errorMessage = "Password is required"
                                            message.isError = true
                                            return
                                        }
                                        if trimmed.count < User.requiredLength {
                                            message.errorMessage = "Password must be at least \(User.requiredLength) characters long"
                                            message.isError = true
                                            return
                                        }
                                        user.password = try User.encryptPassword(password)
                                        user.alert_day = alertDay
                                        user.alert_time = SharedProperties.formatLocalTime(alertTime)
                                        try userModel.save()
                                        let username = user.username
                                        let descriptor = FetchDescriptor<Item>(
                                            predicate: #Predicate { $0.username == username }
                                        )
                                        let userItems = try userModel.fetch(descriptor)
                                        NotificationManager.shared.rescheduleAll(items: userItems, user: user)
                                        message.errorMessage = "Updated successfully!"
                                        message.isError = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0){
                                            message.errorMessage = ""
                                        }
                                    } catch {
                                        message.errorMessage = error.localizedDescription
                                        message.isError = true
                                    }
                                }
                            }
                            .zeroWasteStyle()

                            Button("Logout") {
                                if let user = UserSession.shared.currentUser {
                                    NotificationManager.shared.rescheduleAll(items: [], user: user)
                                }
                                UserSession.shared.logout()
                                message.errorMessage = ""
                                isNavigateToLogin = true
                            }
                            .zeroWasteStyle()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        HStack{
                            Spacer()
                            if !message.errorMessage.isEmpty {
                                Text(message.errorMessage)
                                    .foregroundColor(message.isError ? .red : .blue)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        
                        Button("Delete my account") { showDeleteConfirm = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.gray)
                    }
                }
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onAppear{
                if let user = userSession.currentUser{
                    password = User.decryptPassword(user.password) ?? ""
                    alertDay = user.alert_day
                    if let parsedTime = SharedProperties.parseLocalTime(user.alert_time) { alertTime = parsedTime }
                }
            }
            FormAvatarImage(imageName: "Usersetting", formTop: formTop)
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    guard let user = UserSession.shared.currentUser else { return }
                    do {
                        // Fetch and delete all items for this user
                        let username = user.username
                        let fetch = FetchDescriptor<Item>(predicate: #Predicate { $0.username == username })
                        let userItems = try userModel.fetch(fetch)
                        // Cancel any pending notifications for these items
                        userItems.forEach { NotificationManager.shared.cancelForItemCode($0.itemCode) }
                        for it in userItems { userModel.delete(it) }
                        try userModel.save()
                        
                        // Delete the user
                        try userModel.delete(user)
                        try userModel.save()
                        
                        UserSession.shared.logout()
                        isNavigateToLogin = true
                        
                    } catch {
                        message.errorMessage = error.localizedDescription
                        message.isError = true
                    }
                }
            }
        } message: {
            Text("Deleting your account will also permanently remove all your items.")
        }
        .background(
            Image("Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    UserSettingView()
        .modelContainer(for: User.self, inMemory: true)
}
