# Using the xAI Grok LLM

xAI’s Grok is a large language model (LLM) developed by Elon Musk’s AI startup, xAI, to compete with leading AI systems like OpenAI’s GPT-4. Launched in 2023, Grok is designed to handle a variety of tasks, including answering questions, assisting with writing, and solving coding problems. It is integrated with the social media platform X (formerly Twitter), providing users with real-time information and a conversational AI experience.

Grok has undergone several iterations, with Grok-2 being released in August 2024. This version introduced image generation capabilities, enhancing its versatility. xAI has also made Grok-1 open-source, allowing developers to access its weights and architecture for further research and application development.

To support Grok’s development, xAI has invested in substantial computational resources, including the Colossus supercomputer, which utilizes 100,000 Nvidia H100 GPUs, positioning it as one of the most powerful AI training systems globally. 


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
    
    private static func makeRequest<T: Encodable>(endpoint: String, body: T)
                                             -> String {
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
    
    static func chat(messages: [[String: String]], maxTokens: Int = 25,
                                temperature: Double = 0.3) -> String {
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
              let message = firstChoice["message"]
                                      as? [String: Any],
              let content = message["content"] as? String else {
            return ""
        }
        return content
    }
}

// Usage functions:
func summarize(text: String, maxTokens: Int = 40) -> String {
    X_GROK.chat(messages: [
      ["role": "system",
       "content":
       "You are a helpful assistant that summarizes text concisely."],
      ["role": "user", "content": text]
    ], maxTokens: maxTokens)
}

func questionAnswering(question: String) -> String {
    X_GROK.chat(messages: [
        ["role": "system",
         "content":
         "You are a helpful assistant that answers questions directly and concisely."],
        ["role": "user", "content": question]
    ], maxTokens: 25)
}

func completions(promptText: String, maxTokens: Int = 25) -> String {
    X_GROK.chat(messages: [["role": "user", "content": promptText]],
                           maxTokens: maxTokens)
}
~~~~~~~~

This Swift code defines a client library, **X_GROK**, to interact with the xAI Grok Large Language Model (LLM) API. It leverages Swift’s Foundation framework to handle HTTP requests and JSON encoding/decoding. The library retrieves the API key from the environment variable X_GROK_API_KEY and sets the base URL for the API. It specifies a default model, grok-beta, for generating responses.

The core functionality is encapsulated in the makeRequest function, which constructs and sends HTTP POST requests to the API. It accepts an endpoint and a request body conforming to the Encodable protocol. The function sets the necessary HTTP headers, including Content-Type and Authorization, and encodes the request body into JSON. To handle the asynchronous nature of network calls synchronously, it employs a semaphore, ensuring the function waits for the response before proceeding. The response is then returned as a string.

The chat function utilizes makeRequest to send chat messages to the API. It constructs a ChatRequest struct with parameters like the model, messages, maximum tokens, and temperature. After receiving the response, it parses the JSON to extract the generated content. Additionally, the code provides utility functions **summarize**, **questionAnswering**, and **completions** which use the **chat** function to perform specific tasks such as text summarization, question answering, and text completion, respectively.


Here is the test/example code for this library:

{lang="swift",linenos=off}
~~~~~~~~
import XCTest
@testable import X_GROK_swift

final class X_GROK_swiftTests: XCTestCase {
  func testExample() {
    print("Starting tests...")
    let prompt = "He walked to the river and looked at"
    let ret = completions(promptText: prompt, maxTokens: 200)
    print("** ret from X_GROK API call:", ret)
    let question = "Where was Leonardo da Vinci born?"
    let answer = questionAnswering(question: question)
    print("** answer from X_GROK API call:", answer)
    let text = "Jupiter is the fifth planet from the Sun and the largest in the Solar System. It is a gas giant with a mass one-thousandth that of the Sun, but two-and-a-half times that of all the other planets in the Solar System combined. Jupiter is one of the brightest objects visible to the naked eye in the night sky, and has been known to ancient civilizations since before recorded history. It is named after the Roman god Jupiter.[19] When viewed from Earth, Jupiter can be bright enough for its reflected light to cast visible shadows,[20] and is on average the third-brightest natural object in the night sky after the Moon and Venus."
    let summary = summarize(text: text)
       print("** generated summary: ", summary)
    }
}
~~~~~~~~

Here is the example code output:

{linenos=off}
~~~~~~~~
Starting tests...
** ret from X_GROK API call: He walked to the river and looked at the water flowing gently by. The serene scene provided a moment of peace, as he watched the ripples dance in the sunlight. The sound of the water was soothing, almost like a lullaby, calming his thoughts and grounding him in the present. He felt a deep connection to nature, the river's timeless flow reminding him of life's continuous journey.
** answer from X_GROK API call: Leonardo da Vinci was born in the town of Vinci, in the region of Tuscany, Italy.
** generated summary:  Jupiter, the fifth planet from the Sun, is the largest in our Solar System, classified as a gas giant with a mass significantly greater than all other planets combined. It's one of the brightest objects
~~~~~~~~

