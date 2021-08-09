# Using the OpenAI APIs

I have been working as an artificial intelligence practitioner since 1982 and the capability of the beta OpenAI APIs is the most impressive thing that I have seen (so far!) in my career. These APIs use the GPT-3 model.

I recommend reading the online documentation for the [online documentation for the APIs](https://beta.openai.com/docs/introduction/key-concepts) to see all the capabilities of the beta OpenAI APIs.  Let's start by jumping into the example code that is a GitHub repository [https://github.com/mark-watson/OpenAI_swift](https://github.com/mark-watson/OpenAI_swift) that you can use in your projects.

{lang="swift",linenos=on}
~~~~~~~~
~~~~~~~~


The library that I wrote for this chapter supports three functions: for completing text, summarizing text, and answering general questions. The single OpenAI model that the beta OpenAI APIs use is fairly general purpose and can generate cooking directions when given an ingredient list, grammar correction, write an advertisement from a product description, generate spreadsheet data from data descriptions in English text, etc. 

Given the examples from [https://beta.openai.com](https://beta.openai.com) and the Clojure examples here, you should be able to modify my example code to use any of the functionality that OpenAI documents.

We will look closely at the function **completions** and then just look at the small differences to the other two example functions. The definitions for all three exported functions are kept in the file **src/openai_api/core.clj***. You need to request an API key (I had to wait a few weeks to recieve my key) and set the value of the environment variable **OPENAI_KEY** to your key. You can add a statement like:

{linenos=off}
~~~~~~~~
export OPENAI_KEY=sa-hdffds7&dhdhsdgffd
~~~~~~~~

to your **.profile** or other shell resource file.

While I sometimes use pure Clojure libraries to make HTTP requests, I prefer using the **curl** utility to experiment with API calls from the command line before starting to write any code.

An example **curl** command line call to the beta OpenAI APIs is:

{lang="bash",linenos=on}
~~~~~~~~
curl \
  https://api.openai.com/v1/engines/davinci/completions \
   -H "Content-Type: application/json"
   -H "Authorization: Bearer sa-hdffds7&dhdhsdgffd" \
   -d '{"prompt": "The President went to Congress", \
        "max_tokens": 22}'
~~~~~~~~

Here the API token "sa-hdffds7&dhdhsdgffd" on line 4 is made up - that is not my API token. All of the OpenAI APIs expect JSON data with query parameters. To use the completion API, we set values for **prompt** and **max_tokens**. The value of **max_tokens** is the requested number of returns words or tokens. We will look at several examples later.

In the file **Sources/OpenAI_swift/OpenAI_swift.swift** we start with a helper function **openAiHelper** that takes a string with the OpenAI API call arguments then extracts the results from the returned JSON data:

{lang="swift",linenos=on}
~~~~~~~~
func openAiHelper(body: String)  -> String {
    var ret = ""
    var content = "{}"
    let requestUrl = URL(string: openAiHost)!
    var request = URLRequest(url: requestUrl)
    request.httpMethod = "POST"
    request.httpBody = body.data(using: String.Encoding.utf8);
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer " + openai_key, forHTTPHeaderField: "Authorization")
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
        if let error = error {
            print("-->> Error accessing OpenAI servers: \(error)")
            return
        }
        if let data = data, let s = String(data: data, encoding: .utf8) {
            content = s
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
    task.resume()
    CFRunLoopRun()
    let c = String(content)
    let i1 = c.range(of: "\"text\": ")
    if let r1 = i1 {
        let i2 = c.range(of: "\"index\":")
        if let r2 = i2 {
            ret = String(String(String(c[r1.lowerBound..<r2.lowerBound]).dropFirst(9)).dropLast(2))
        }
    }
    return ret
}
~~~~~~~~

I convert JSON data to a sequence ... TBD

The three example functions all use this **openAiHelper** function. The first example function **completions** sets the parameters to complete a text fragment. You have probably seen examples of the OpenAI GPT-3 model writing stories, given a starting sentence. We are using the same model and functionality here:

{lang="swift",linenos=on}
~~~~~~~~
public func completions(promptText: String, maxTokens: Int = 25) -> String {
    let body: String = "{\"prompt\": \"" + promptText + "\", \"max_tokens\": \(maxTokens)" + "}"
    return openAiHelper(body: body)}
~~~~~~~~

Note that the OpenAI models are stochastic. When generating output words (or tokens), the model assigns probabilities to possible words to generate and samples a word using these probabilities. As a simple example, suppose given prompt text "it fell and", then the model could only generate three words, with probabilities for each word based on this prompt text:

- the 0.9
- that 0.1
- a 0.1

The model would *emit* the word **the** 90% of the time, the word **that** 10% of the time, or the word **a** 10% of the time. As a result, the model can generate different completion text for the same text prompt. Let's look at some examples using the same prompt text. Notice the stochastic nature of the returned results with prompt text ""He walked to the river" passed twice to the OpenAI GPT-3 model:

First example:

{lang="bash",linenos=on}
~~~~~~~~
 and sat down thinking, the warm evening clotted with insects. The river lapping the bank in the long grass. He
~~~~~~~~

Another example of text completion:

{lang="bash",linenos=on}
~~~~~~~~
, the beast running slowly behind him. He looked away from the cave now, using rain and clouds as his curtain to hide

~~~~~~~~

The function **summarize** is very similar to the function **completions** except the JSON data passed to the API has a few additional parameters that let the API know that we want a text summary:

- presence_penalty - penalize words found in the original text (we set this to zero)
- temperature - higher values the randomness used to select output tokens. If you set this to zero, then the same prompt text will always yield the same results (I never use a zero value).
- top_p - also affects randomness. All examples I have seen use a value of 1.
- frequency_penalty - penalize using the same words repeatedly (I usually set this to zero, but you should experiment with different values)

When summarizing text, try varying the number of generated tokens to get shorter or longer summaries; in the following examples we ask for 24, 90, and 150 output tokens:

{lang="swift",linenos=on}
~~~~~~~~
public func summarize(text: String, maxTokens: Int = 40) -> String {
    let body: String = "{\"prompt\": \"" + text + "\", \"max_tokens\": \(maxTokens), \"presence_penalty\": 0.0, \"temperature\": 0.3, \"top_p\": 1.0, \"frequency_penalty\": 0.0}"
    return openAiHelper(body: body)}
~~~~~~~~

Notice the stochastic nature of the returned summarization results with prompt text "Jupiter is the fifth planet from the Sun and the largest in the Solar System. It is a gas giant with a mass one-thousandth that of the Sun, but two-and-a-half times that of all the other planets in the Solar System combined. Jupiter is one of the brightest objects visible to the naked eye in the night sky, and has been known to ancient civilizations since before recorded history. It is named after the Roman god Jupiter.[19] When viewed from Earth, Jupiter can be bright enough for its reflected light to cast visible shadows,[20] and is on average the third-brightest natural object in the night sky after the Moon and Venus.":

First summarization example:

{lang="bash",linenos=on}
~~~~~~~~
 Jupiter is a gas giant because it is predominantly composed of hydrogen and helium; it has a solid core, but it has no surface. Jupiter is a gas giant because it is predominantly composed"
 ~~~~~~~~

Another summarization example:

{lang="bash",linenos=on}
~~~~~~~~
The planet is usually the fourth-brightest in the night sky, after the Sun, Venus and the Moon.

Jupiter is a gas giant because it is predominantly composed of hydrogen
~~~~~~~~

The function **answerQuestion** is very similar to the function **summarize** except the JSON data passed to the API has one additional parameter that let the API know that we want a question answered:

- stop - The OpenAI API examples use the value: **[\n]**, which is what I use here.

We also need to prepend the string "nQ: " to the prompt text.

Additionally, the model returns a series of answers with the string "nQ:" acting as a delimiter between the answers. 

{lang="swift",linenos=on}
~~~~~~~~
public func questionAnsweering(question: String) -> String {
    let body: String = "{\"prompt\": \"nQ: " + question + " nA:\", \"max_tokens\": 25, \"presence_penalty\": 0.0, \"temperature\": 0.3, \"top_p\": 1.0, \"frequency_penalty\": 0.0 , \"stop\": [\"\\n\"]}"
    let answer = openAiHelper(body: body)
    if let i1 = answer.range(of: "nQ:") {
        return String(answer[answer.startIndex..<i1.lowerBound])
        //return String(answer.prefix(i1.lowerBound))
    }
    return answer}
~~~~~~~~

I strongly urge you to add a debug printout to the question answering code to print the full answer before we check for the delimiter string. For some questions, the OpenAI APIs generate a series of answers that increase in generality. In the example code we just take the most specific answer.

Let's look at a few question answering examples and we will discuss possible problems and workarounds. The first two examples ask the same question and get back different, but reasonable answers. The third example asks a general question. The GPT-3 model is trained using a massive amount of text from the web which is why it can generate reasonable answers. Here are two examples for answering the question "Where was Leonardo da Vinci born?":

{lang="bash",linenos=on}
~~~~~~~~
In Vinci, Italy.
~~~~~~~~

And another generated output for the same question:

{lang="bash",linenos=on}
~~~~~~~~
In Italy.
~~~~~~~~

In addition to reading the beta OpenAI API documentation you might want to read general material on the use of OpenAI's GPT-3 model. Since the APIs we are using are beta they may change. I will update this chapter and the source code on GitHub if the APIs change.
