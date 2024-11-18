# Using APIs for Anthropic Claude LLMs

Here, I decided to not write a new client library for the Anthropic APIs since there are several existing high quality libraries for accessing the Anthropic Claude APIs.

This is not a strong recommendation of one Anthropic client library over another, but I very much enjoy using the following project because of the simplicity of it’s API:

{linenos=off}
~~~~~~~~
https://github.com/fumito-ito/AnthropicSwiftSDK
~~~~~~~~

My examples using this library to access the Anthropic Claude APIs can be found here:

{linenos=off}
~~~~~~~~
https://github.com/mark-watson/Anthropic_swift_examples
~~~~~~~~

You need to set the following environment variable for your person Anthropic API key: Anthropic API key:

{linenos=off}
~~~~~~~~
ANTHROPIC_API_KEY
~~~~~~~~

that you can get by creating an account:

{linenos=off}
~~~~~~~~
https://console.anthropic.com
~~~~~~~~

Note that there is no library implemented in this chapter.


## Running the examples

All of the examples are packaged as Swift tests so git clone my examples repository [https://github.com/mark-watson/Anthropic_swift_examples](https://github.com/mark-watson/Anthropic_swift_examples) and run:

{linenos=off}
~~~~~~~~
swift test
~~~~~~~~

The test Swift source file defines a test class (just the first few lines shown here):

{lang="swift",linenos=off}
~~~~~~~~
final class Anthropic_swift_examplesTests: XCTestCase {
  let text1 = "If Mary is 42, Bill is 27, and Sam is 51, what are their pairwise age differences. Please be concise."
  func testExample() async throws {
    let key = 
      ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!
    let anthropic = Anthropic(apiKey: key)
    let message = Message(role: .user,
                          content: [.text(text1)])
    let response =
      try await
        anthropic.messages.createMessage([message],
                                         maxTokens: 400)
~~~~~~~~

If you print the value of **response** you see:

{linenos=off}
~~~~~~~~
MessagesResponse(id: "msg_02RvimFjHFFmaV4n994J9wck", type: AnthropicSwiftSDK.MessagesResponseType.message, role: AnthropicSwiftSDK.Role.assistant, content: [AnthropicSwiftSDK.Content.text("The pairwise age differences are:\n\nMary and Bill: 15 years\nMary and Sam: 9 years\nBill and Sam: 24 years", cacheControl: nil)], model: Optional(AnthropicSwiftSDK.Model.claude_3_Opus), stopReason: Optional(AnthropicSwiftSDK.StopReason.endTurn), stopSequence: nil, usage: AnthropicSwiftSDK.TokenUsage(inputTokens: Optional(38), outputTokens: Optional(38)))
~~~~~~~~

If you print the value of **response.content** you see:

{linenos=off}
~~~~~~~~
[AnthropicSwiftSDK.Content.text("The pairwise age differences are:\n\nMary and Bill: 15 years\nMary and Sam: 9 years\nBill and Sam: 24 years", cacheControl: nil)]
~~~~~~~~

For normal use you just want the string contents of the model’s response to your prompt, so use:

{lang="swift",linenos=off}
~~~~~~~~
  for content in response.content {
    if case let .text(text, _) = content {
        print("Assistant's response: \(text)")
    }
  }
~~~~~~~~

That outputs:

{linenos=off}
~~~~~~~~
Assistant's response: The pairwise age differences are:

Mary and Bill: 15 years
Mary and Sam: 9 years
Bill and Sam: 24 years
~~~~~~~~

In the general case of the Claude model returning images, tools used, and tool results, use code like this:

{lang="swift",linenos=off}
~~~~~~~~
  for content in response.content {
     switch content {
       case .text(let text, _):
         print("Assistant's response: \(text)")
       case .image(let imageContent, _):
         print("imageContent: \(imageContent)")
         break
       case .document(let documentContent, _):
         print("documentContent: \(documentContent)")
         break
       case .toolResult(let toolResult):
         print("toolResult: \(toolResult)")
         break
       case .toolUse(let toolUse):
         print("toolUse: \(toolUse)")
         break
       }
     }
  }
~~~~~~~~
