//
//  ContentView.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 6/9/25.
//

import SwiftUI

struct ContentView: View {
    @State private var username = ""
    @State private var password = ""
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Image("Background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Fixed-position title icon
                Image("ZeroWasteIconTitle")
                    .resizable()
                    .frame(width: 150, height: 150)
                    .position(x: 90, y: 60) // X: top, Y: left

                VStack {
                    Spacer()

                    // Login Card with floating icon
                    ZStack(alignment: .top) {
                        // White container
                        VStack(spacing: 20) {
                            Spacer().frame(height: 30) // Space for icon overlap

                            TextField("Username", text: $username)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray))

                            SecureField("Password", text: $password)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray))

                            Spacer().frame(height: 20)

                            HStack {
                                Button(action: {
                                    // Login action
                                }) {
                                    Text("Login")
                                        .font(.system(size: 24))
                                        .frame(minWidth: 80)
                                        .padding()
                                        .background(Color.gray.opacity(0.3))
                                        .cornerRadius(10)
                                        .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.black, lineWidth: 1)
                                                )
                                }
                                .foregroundColor(.black)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 8) {
                                    Button("Register") {
                                        // Register action
                                    }
                                    .foregroundColor(.blue)

                                    Button("Forgot password") {
                                        // Forgot password action
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                            .padding([.horizontal, .bottom])
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 40)
                        .padding(.bottom)
                        .background(Color.white)
                        .cornerRadius(20)
                        .padding(.leading, 16)
                        .padding(.trailing, 55)
                        .shadow(radius: 10)

                        // Floating login icon
                        Image("Login")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                            .offset(x: -23, y: -50)
                    }

                    Spacer()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
