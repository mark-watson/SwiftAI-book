import Foundation

struct OpenAI {
    private static let key = ProcessInfo.processInfo.environment["OPENAI_KEY"]!
    private static let baseURL = "https://api.openai.com/v1"
    
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [[String: String]]
        let max_tokens: Int
        let temperature: Double
    }
    
    private struct EmbeddingRequest: Encodable {
        let model: String
        let input: String
    }
    
    private static func makeRequest<T: Encodable>(endpoint: String, body: T) -> String {
        var responseString = ""
        let url = URL(string: baseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(body)
        
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
            }
            if let data = data {
                responseString = String(data: data, encoding: .utf8) ?? "{}"
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        
        return responseString
    }
    
    static func chat(messages: [[String: String]], maxTokens: Int = 25, temperature: Double = 0.3) -> String {
        let chatRequest = ChatRequest(
            model: "gpt-4o-mini",
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature
        )
        
        let response = makeRequest(endpoint: "/chat/completions", body: chatRequest)
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return ""
        }
        return content
    }
    
    static func embeddings(text: String) -> [Float] {
        let embeddingRequest = EmbeddingRequest(
            model: "text-embedding-ada-002",
            input: text
        )
        
        let response = makeRequest(endpoint: "/embeddings", body: embeddingRequest)
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let embedding = dataArray.first?["embedding"] as? [NSNumber] else {
            return [1.23]
        }
        return embedding.map { number in Float(truncating: number) }
    }
}

// Usage functions:
func summarize(text: String, maxTokens: Int = 40) -> String {
    OpenAI.chat(messages: [
        ["role": "system", "content": "You are a helpful assistant that summarizes text concisely."],
        ["role": "user", "content": text]
    ], maxTokens: maxTokens)
}

func questionAnswering(question: String) -> String {
    OpenAI.chat(messages: [
        ["role": "system", "content": "You are a helpful assistant that answers questions directly and concisely."],
        ["role": "user", "content": question]
    ], maxTokens: 25)
}

func completions(promptText: String, maxTokens: Int = 25) -> String {
    OpenAI.chat(messages: [["role": "user", "content": promptText]], maxTokens: maxTokens)
}