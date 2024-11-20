# Using Groq APIs to Open Weight LLM Models

Groq develops custom silicon for fast LLM inference. 

Groq’s API service supports a variety of openly available models, including:

- Llama 3.1 Series: Models like llama-3.1-70b-versatile, llama-3.1-8b-instant, and others, offering up to 128K context windows.
- Llama 3.2 Vision Series: Multimodal models such as llama-3.2-90b-vision-preview and llama-3.2-11b-vision-preview, capable of processing both text and image inputs.
- Llama 3 Groq Tool Use Models: Specialized for function calling, including llama3-Groq-70b-8192-tool-use-preview and llama3-Groq-8b-8192-tool-use-preview.
- Mixtral 8x7b: A model with a 32,768-token context window, suitable for extensive context applications.
- Gemma Series: Models like gemma2-9b-it and gemma-7b-it, each with an 8,192-token context window.
- Whisper Series: Models such as whisper-large-v3 and whisper-large-v3-turbo, designed for audio transcription and translation tasks.

To obtain an API key, visit Groq’s API keys management page:

{linenos=off}
~~~~~~~~
https://console.groq.com/keys
~~~~~~~~

The code for this chapter can be found here:

{linenos=off}
~~~~~~~~
https://github.com/mark-watson/Groq_swift
~~~~~~~~


## Implementation of a Client Library for the Groq APIs

Groq supports the OpenAI APIs so the following client library for Groq is similar to what I wrote previously for OpenAI:

{lang="swift",linenos=off}
~~~~~~~~
import Foundation

struct Groq {
    private static let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"]!
    private static let baseURL = "https://api.groq.com/openai/v1/"
    
    private static let MODEL = "llama3-8b-8192"

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
    
    static func chat(messages: [[String: String]],
                                maxTokens: Int = 25,
                                temperature: Double = 0.3)
                                                 -> String {
        let chatRequest = ChatRequest(
            model: MODEL,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature
        )
        
        let response = makeRequest(endpoint: "/chat/completions", body: chatRequest)
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
                         as? [String: Any],
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
    Groq.chat(messages: [
      ["role": "system",
       "content":
       "You are a helpful assistant that summarizes text concisely"],
      ["role": "user", "content": text]
    ], maxTokens: maxTokens)
}

func questionAnswering(question: String) -> String {
    Groq.chat(messages: [
      ["role": "system",
       "content":
       "You are a helpful assistant that answers questions directly and concisely."],
      ["role": "user", "content": question]
    ], maxTokens: 25)
}

func completions(promptText: String, maxTokens: Int = 25) -> String {
    Groq.chat(messages: [
        ["role": "system", "content": "You complete text"],
        ["role": "user", "content": promptText]],
        maxTokens: maxTokens)
}
~~~~~~~~

### Explanation of the Swift Groq API Code

#### 1. Setting Up the API
- The `Groq` struct is designed to interact with the Groq API, mimicking OpenAI's API.
- **API Key**: Retrieved from the environment variable `GROQ_API_KEY`.
- **Base URL**: The API's base endpoint is `https://api.groq.com/openai/v1/`.
- **Model**: The model being used is predefined as `llama3-8b-8192`.


#### 2. Structure of a Chat Request
- A private struct, `ChatRequest`, defines the JSON payload for requests:
  - `model`: The model name.
  - `messages`: A history of the conversation.
  - `max_tokens`: Limits the number of tokens in the response.
  - `temperature`: Controls randomness in the responses.

---

#### 3. Making an HTTP POST Request
- The `makeRequest` function handles API communication:
  - Constructs the full URL by appending the endpoint to the base URL.
  - Sets up a POST request with:
    - JSON content type.
    - Authorization header using the API key.
  - Encodes the request body into JSON using `JSONEncoder`.
  - Sends the request asynchronously but waits for the response using a semaphore.
  - Parses the response data into a string.

---

#### 4. Chat Functionality
- The `chat` function simplifies sending messages to the API:
  - Constructs a `ChatRequest` object with the given parameters.
  - Sends the request to the `/chat/completions` endpoint.
  - Processes the JSON response to extract the model’s reply from the `choices` array.

---

#### 5. Usage Functions
**summarize**
- Summarizes a text.
- Sends a conversation history where the system is described as "a helpful assistant that summarizes text concisely."

```swift
summarize(text: String, maxTokens: Int = 40)
```

**questionAnswering**
- Answers a user-provided question directly.
- Sends a conversation history where the system is described as "a helpful assistant that answers questions directly and concisely."

**completions**
- Generates continuations for a given user prompt.

## Running the Tests

Here is the test/example code for this library:

{lang="swift",linenos=off}
~~~~~~~~
import XCTest
@testable import Groq_swift

final class Groq_swiftTests: XCTestCase {
  func testExample() {
    print("Starting tests...")
    let prompt = "He walked to the river and looked at"
    let ret = completions(promptText: prompt, maxTokens: 200)
    print("** ret from Groq API call:", ret)
    let question = "Where was Leonardo da Vinci born?"
    let answer = questionAnswering(question: question)
    print("** answer from Groq API call:", answer)
    let text = "Jupiter is the fifth planet from the Sun and the largest in the Solar System. It is a gas giant with a mass one-thousandth that of the Sun, but two-and-a-half times that of all the other planets in the Solar System combined. Jupiter is one of the brightest objects visible to the naked eye in the night sky, and has been known to ancient civilizations since before recorded history. It is named after the Roman god Jupiter.[19] When viewed from Earth, Jupiter can be bright enough for its reflected light to cast visible shadows,[20] and is on average the third-brightest natural object in the night sky after the Moon and Venus."
    let summary = summarize(text: text)
    print("** generated summary: ", summary)
  }
}
~~~~~~~~

Here is sample output from this example use of the library:

{linenos=off}
~~~~~~~~
Starting tests...

** ret from Groq API call: the calm water, feeling the warm sun on his face and the gentle breeze rustling his hair. The sound of the water lapping against the shore was soothing, and he closed his eyes, taking a deep breath to clear his mind.

** answer from Groq API call: Leonardo da Vinci was born on April 15, 1452, in Vinci, Italy.

** generated summary:  Here's a concise summary:

Jupiter is the largest planet in our Solar System, a gas giant with a mass 2.5 times that of all other planets combined. It's the fifth planet
~~~~~~~~
