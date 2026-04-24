import XCTest

@testable import OpenAI_swift

final class OpenAI_swiftTests: XCTestCase {
    func testExample() {
        print("Starting tests...")
        let embeds = OpenAI.embeddings(text: "Congress passed tax laws.")
        print(embeds[..<min(10, embeds.count)])
        let prompt = "He walked to the river and looked at"
        let ret = completions(promptText: prompt)
        print("** ret from OpenAI API call:", ret)
        let question = "Where was Leonardo da Vinci born?"
        let answer = questionAnswering(question: question)
        print("** answer from OpenAI API call:", answer)
        let text = "Jupiter is the fifth planet from the Sun and the largest in the Solar System. It is a gas giant with a mass one-thousandth that of the Sun, but two-and-a-half times that of all the other planets in the Solar System combined. Jupiter is one of the brightest objects visible to the naked eye in the night sky, and has been known to ancient civilizations since before recorded history. It is named after the Roman god Jupiter.[19] When viewed from Earth, Jupiter can be bright enough for its reflected light to cast visible shadows,[20] and is on average the third-brightest natural object in the night sky after the Moon and Venus."
        let summary = summarize(text: text)
        print("** generated summary: ", summary)
    }
}
