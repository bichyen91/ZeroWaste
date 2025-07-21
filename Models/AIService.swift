//
//  AIService.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/7/25.
//

import Foundation

class AIService {
    static let shared = AIService()
    private let apiKey = "AIzaSyB9CbCrv2w7qD-VxJVTj6Fj9Zd_jhcQQWw"
    
    func predictExpiredDate(itemName: String, purchaseDate: Date, completion: @escaping (Date?) -> Void){
        let purchaseDateString = SharedProperties.parseDateToString(purchaseDate, to: "yyyy_MM-dd")
        let prompt = "Given \(itemName) and the purchase date \(purchaseDateString), what is the general expiration date in yyyy-MM-dd format? Only return the expiration date."
        
        //Connect Gemini API, return nil if URL invalid
        guard let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)") else {
            completion(nil)
            return
        }
        
        //Docs: https://ai.google.dev/gemini-api/docs/text-generation#apps-script
        
        //Gemini API format in JSON structure
        let payload:[String: Any] = [
            "contents": [
                "parts": [
                    ["text": prompt]
                ]
            ]
        ]
        
        //URL setup
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        //Convert to JSON and add to request body, return nil if fail
        do{
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) {data, _, error in
            //Guard if no network error or no data receive
            guard error == nil, let data = data else {
                print("Error")
                completion(nil)
                return
            }
            
            var predictedDate: Date?
            //Gemini response structure: data['candidates'][0]['content']['parts'][0]['text']
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String,
               let range = text.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression){
                print("Prompt: ", prompt)
                print("Gemini Output:", text)
                let dateString = String(text[range])
                predictedDate = SharedProperties.parseStringToDate(from: dateString, to: "yyyy-MM-dd")
                
            }
            else {
                predictedDate = Calendar.current.date(byAdding: .day, value: 7, to: purchaseDate)
            }
            
            DispatchQueue.main.async {
                completion(predictedDate)
            }
        }
        .resume()
    }
}
