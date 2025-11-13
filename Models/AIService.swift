//
//  AIService.swift
//  ZeroWaste
//
//  Created by Yannie Chiem on 7/7/25.
//

import Foundation

class AIService {
    static let shared = AIService()
    private let apiKey: String = {
        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path),
            let key = dict["Gemini API Key"] as? String
        else {
            fatalError("No Key Found")
        }
        return key
    }()
    
    func predictExpiredDate(itemName: String, purchaseDate: Date, completion: @escaping (Date?) -> Void){
        let purchaseDateString = SharedProperties.parseDateToString(purchaseDate, to: "yyyy-MM-dd")
        let prompt = "Given \(itemName) and the purchase date \(purchaseDateString), what is the general expiration date in yyyy-MM-dd format? Only return the expiration date."
        
        //Connect Gemini API, return nil if URL invalid
        // guard let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)") else {
//        guard let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
                guard let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=\(apiKey)") else {
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
        
        URLSession.shared.dataTask(with: request) {data, response, error in
            //Guard if no network error or no data receive
            guard error == nil, let data = data else {
                if let err = error { print("Gemini request error:", err.localizedDescription) }
                if let http = response as? HTTPURLResponse { print("Gemini status:", http.statusCode) }
                completion(nil)
                return
            }
            if let http = response as? HTTPURLResponse { print("Gemini status:", http.statusCode) }
            
            var predictedDate: Date?
            //Gemini response structure: data['candidates'][0]['content']['parts'][0]['text']
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String,
               let range = text.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression){
                print("Prompt: ", prompt)
                print("Gemini Output:", text, "\n")
                let dateString = String(text[range])
                predictedDate = SharedProperties.parseStringToDate(from: dateString, to: "yyyy-MM-dd")
                
            }
            else {
                if let raw = String(data: data, encoding: .utf8) {
                    print("Gemini raw response:", raw)
                }
                predictedDate = Calendar.current.date(byAdding: .day, value: 7, to: purchaseDate)
            }
            
            DispatchQueue.main.async {
                completion(predictedDate)
            }
        }
        .resume()
    }
}
