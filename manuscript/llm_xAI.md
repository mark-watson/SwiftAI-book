# Using the xAI Grok LLM

xAI’s Grok is a large language model (LLM) developed by Elon Musk’s AI startup, xAI, to compete with leading AI systems like OpenAI’s GPT-4. Launched in 2023, Grok is designed to handle a variety of tasks, including answering questions, assisting with writing, and solving coding problems. It is integrated with the social media platform X (formerly Twitter), providing users with real-time information and a conversational AI experience. ￼

Grok has undergone several iterations, with Grok-2 being released in August 2024. This version introduced image generation capabilities, enhancing its versatility. xAI has also made Grok-1 open-source, allowing developers to access its weights and architecture for further research and application development. ￼￼ To support Grok’s development, xAI has invested in substantial computational resources, including the Colossus supercomputer, which utilizes 100,000 Nvidia H100 GPUs, positioning it as one of the most powerful AI training systems globally. 


## Implementation of a Grok API Client Library

The code for my xAI Grok client code can be found here:

{linenos=off}
~~~~~~~~
https://github.com/mark-watson/X_GROK_swift
~~~~~~~~

The Grok is similar to the OpenAI APIs so I copied the code we saw earlier that I wrote for OpenAI and made the simple modifications required to access Grok APIs (code discussion appears after this listing):

{lang="swift",linenos=off}
~~~~~~~~
import Foundation

// xAI Grog LLM client library

struct X_GROK {
    private static let key = ProcessInfo.processInfo.environment["X_GROK_API_KEY"]!
    private static let baseURL = "https://api.x.ai/v1"
    
    private static let MODEL = "grok-beta"

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [[String: String]]
        let max_tokens: Int
        let temperature: Double
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
            model: MODEL,
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
}

// Usage functions:
func summarize(text: String, maxTokens: Int = 40) -> String {
    X_GROK.chat(messages: [
        ["role": "system", "content": "You are a helpful assistant that summarizes text concisely."],
        ["role": "user", "content": text]
    ], maxTokens: maxTokens)
}

func questionAnswering(question: String) -> String {
    X_GROK.chat(messages: [
        ["role": "system", "content": "You are a helpful assistant that answers questions directly and concisely."],
        ["role": "user", "content": question]
    ], maxTokens: 25)
}

func completions(promptText: String, maxTokens: Int = 25) -> String {
    X_GROK.chat(messages: [["role": "user", "content": promptText]], maxTokens: maxTokens)
}
~~~~~~~~

This Swift code defines a client library, **X_GROK**, to interact with the xAI Grok Large Language Model (LLM) API. It leverages Swift’s Foundation framework to handle HTTP requests and JSON encoding/decoding. The library retrieves the API key from the environment variable X_GROK_API_KEY and sets the base URL for the API. It specifies a default model, grok-beta, for generating responses.

The core functionality is encapsulated in the makeRequest function, which constructs and sends HTTP POST requests to the API. It accepts an endpoint and a request body conforming to the Encodable protocol. The function sets the necessary HTTP headers, including Content-Type and Authorization, and encodes the request body into JSON. To handle the asynchronous nature of network calls synchronously, it employs a semaphore, ensuring the function waits for the response before proceeding. The response is then returned as a string.

The chat function utilizes makeRequest to send chat messages to the API. It constructs a ChatRequest struct with parameters like the model, messages, maximum tokens, and temperature. After receiving the response, it parses the JSON to extract the generated content. Additionally, the code provides utility functions **summarize**, **questionAnswering**, and **completions** which use the **chat** function to perform specific tasks such as text summarization, question answering, and text completion, respectively.
