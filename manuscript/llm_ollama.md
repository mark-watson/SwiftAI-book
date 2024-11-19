# Using Ollama to Run Local LLMs

Ollama is a program and framework written in Go that allows you to download, run models on the command line, and call using a REST style interface. You need to downnload the Ollama executable for your operation system at [https://ollama.com](https://ollama.com).

Similarly to our use of a third party for accessing the Anthropic Clause models, here we will not write a wrapper libary. The example code for ths chapter is in the test code for the Swift project in the GitHub repository [https://github.com/mark-watson/Ollama_swift_examples](https://github.com/mark-watson/Ollama_swift_examples).

We use the library in the GitHub repository [https://github.com/mattt/ollama-swift](https://github.com/mattt/ollama-swift).

## Running the Ollama Service

Assuming you have Ollama installed, download the following model that required two gigabytes of disk space:

{linenos=off}
~~~~~~~~
ollama pull llama3.2:latest
~~~~~~~~

When the model is downloaded it is also cached for future use on your laptop.

Here is the test/example code we will run:

{lang="swift",linenos=off}
~~~~~~~~
import XCTest
import Ollama

final class Ollama_swift_examplesTests: XCTestCase {
    let text1 = "If Mary is 42, Bill is 27, and Sam is 51, what are their pairwise age differences."
    let client = Ollama.Client.default // http://localhost:11434 endpoint
    func testExample() async throws {
      let response = try await client.chat(
        model: "llama3.2:latest",
        messages: [
            .system("You are a helpful assistant who completes text and also answers questions. You are always concise."),
            .user(text1),
            .user("what if Sam is 52?")
        ])
        print(response.message.content)
    }
}
~~~~~~~~

The output looks like:

{linenos=off}
~~~~~~~~
Pairwise age differences:

- Mary - Bill: |42 - 27| = 15
- Mary - Sam: |42 - 51| = 9
- Bill - Sam: |27 - 51| = 24

If Sam is 52:
- Mary - Bill: |42 - 27| = 15
- Mary - Sam: |42 - 52| = 10
- Bill - Sam: |27 - 52| = 25
~~~~~~~~

The **ollama_swift** library also supports text generation. You can also do single shot text generation using the code in the previous example, but only using one **user** call, for example:

{lang="swift",linenos=off}
~~~~~~~~
final class Ollama_swift_examplesTests: XCTestCase {
    let text1 = "What is the capital of Germany?"
    let client = Ollama.Client.default
    func testExample() async throws {
      let response = try await client.chat(
        model: "llama3.2:latest",
        messages: [
            .system("You are a helpful assistant who completes text and also answers questions. You are always concise."),
            .user(text1),
        ])
        print(response.message.content)
    }
}
~~~~~~~~

The output looks like:

{linenos=off}
~~~~~~~~
The capital of Germany is Berlin.
~~~~~~~~

## Ollama Wrap Up

This is a short chapter but an important one. I do over half my work with LLMs running locally on my laptop using Ollama, with the rest of my work using OpenAI, Anthropic, and Groq commercial APIs.

