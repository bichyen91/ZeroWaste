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
                                        user.password = try User.encryptPassword(password)
                                        user.alert_day = alertDay
                                        user.alert_time = SharedProperties.parseDateToString(alertTime, to: "HH:mm")
                                        try userModel.save()
                                        message.errorMessage = "Updated successfully!"
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0){
                                            message.errorMessage = ""
                                        }
                                    } catch {
                                        message.errorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .zeroWasteStyle()

                            Button("Logout") {
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
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        
                        Button("Delete my account") {
                            Task {
                                do {
                                    if let user = UserSession.shared.currentUser {
                                        try userModel.delete(user)
                                        message.errorMessage = ""
                                        UserSession.shared.logout()
                                        isNavigateToLogin = true
                                    }
                                } catch {
                                    message.errorMessage = error.localizedDescription
                                }
                            }
                        }
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
                    if let parsedTime = SharedProperties.parseStringToDate(from: user.alert_time, to: "HH:mm"){
                        alertTime = parsedTime
                    }
                }
            }
            FormAvatarImage(imageName: "Usersetting", formTop: formTop)
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
