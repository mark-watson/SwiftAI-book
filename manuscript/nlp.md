# Natural Language Processing Using Apple's Natural Language Framework

I have been working in the field of Natural Language Processing (NLP) since 1985 so I 'lived through' the revolutionary change in NLP that has occurred since 2014: Deep Learning results out-classed results from previous symbolic methods.

https://developer.apple.com/documentation/naturallanguage

I will not cover older symbolic methods of NLP here, rather I refer you to my previous books [Practical Artificial Intelligence Programming With Java](https://leanpub.com/javaai), [Loving Common Lisp, or the Savvy Programmer's Secret Weapon](https://leanpub.com/lovinglisp), and [Haskell Tutorial and Cookbook](https://leanpub.com/haskell-cookbook) for examples. We get better results using Deep Learning (DL) for NLP and the libraries that Apple provides.

You will learn how to apply both DL and NLP by using the state-of-the-art full-feature libraries that Apple provides in their iOS and macOS development tools.


## Using Apple's **NaturalLanguage** Swift Library

We will use one of Apple's NLP libraries consisting of pre-built models in the last chapter of this book. In order to fully understand the example in the last chapter you will need to read Apple's high-level discussion of using CoreML [https://developer.apple.com/documentation/coreml](https://developer.apple.com/documentation/coreml) and their specific support for NLP [https://developer.apple.com/documentation/naturallanguage/](https://developer.apple.com/documentation/naturallanguage/).

There are many pre-trained CoreML compatible models on the web, both from Apple and also from third party (e.g., [https://github.com/likedan/Awesome-CoreML-Models](https://github.com/likedan/Awesome-CoreML-Models)).

Apple also provides tools for converting TensorFlow and PyTorch models to be compatible with CoreML [https://coremltools.readme.io/docs](https://coremltools.readme.io/docs).

## A simple Wrapper Library for Apple's NLP Models

I will not go into too much detail here but I created a small wrapper library for Apple's NLP models that will make it easier for you to jump in and have fun experimenting with them: [https://github.com/mark-watson/Nlp_swift](https://github.com/mark-watson/Nlp_swift).

The main library implementation file uses the **@available(OSX 10.13, *)** attribute to indicate that the following function is available on macOS 10.13 and later versions.

```swift
import Foundation
import NaturalLanguage

let tagger = NSLinguisticTagger(tagSchemes:[.tokenType, .language, .lexicalClass,
    .nameType, .lemma], options: 0) 
let options: NSLinguisticTagger.Options = [.omitPunctuation, .omitWhitespace,
    .joinNames]

@available(OSX 10.13, *)
public func getEntities(for text: String) -> [(String, String)] {
    var words: [(String, String)] = []
    tagger.string = text
    let range = NSRange(location: 0, length: text.utf16.count)
    tagger.enumerateTags(in: range, unit: .word, scheme: .nameType,
    options: options) { tag, tokenRange, stop in
        let word = (text as NSString).substring(with: tokenRange)
        words.append((word, tag?.rawValue ?? "unkown"))
    }
    return words
}

@available(OSX 10.13, *)
public func getLemmas(for text: String) -> [(String, String)] {
    var words: [(String, String)] = []
    tagger.string = text
    let range = NSRange(location: 0, length: text.utf16.count)
    tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, 
            options: options) { tag, tokenRange, stop in
        let word = (text as NSString).substring(with: tokenRange)
        words.append((word, tag?.rawValue ?? "unkown"))
    }
    return words
}
```

The public function **getEntities** takes a String parameter called **text** and returns an array of tuples containing **(String, String)**. Here's a breakdown of what this function does:

- The function initializes an empty array called words to store the extracted entities.
- The line **tagger.string = text** sets the input text for a tagger object. The tagger is an instance of **NSLinguisticTagger**, which is a natural language processing class provided by Apple's Foundation framework.
- The next line creates an **NSRange** object called **range** that represents the entire length of the input text.
- The **tagger.enumerateTags(in:range, unit:.word, scheme:.nameType, options:options)** method is called to iterate over the words in the input text and extract their associated tags. The **in:** parameter specifies the range of the text to process. The **unit:** parameter specifies that the enumeration should be done on a word-by-word basis. The **scheme:** parameter specifies the linguistic scheme to use, in this case, the **.nameType** scheme, which is used to identify named entities. The **options:** parameter specifies additional options or settings for the tagger.
- Inside the enumeration block, the code retrieves the current word and its associated tag using the **tokenRange** and **tag** parameters.
- The line **let word = (text as NSString).substring(with: tokenRange)** extracts the substring corresponding to the current word using **tokenRange**.
- The line **words.append((word, tag?.rawValue ?? "unknown"))** appends a tuple containing the extracted word and its associated tag to the words array. If the tag is nil, it uses the default value of "unknown".
- Finally, the words array is returned, which contains all the extracted entities (words and their associated tags) from the input text.

The public function called **getLemmas** that takes a String parameter called **text** and returns an array of tuples containing **(String, String)**. Here's a breakdown of what the function **getLemmas** is very similar to the last function **getEntities**. The function **getLemmas** does the following:

- The function initializes an empty array called words to store the extracted lemmas.
- The line tagger.string = text sets the input text for a tagger object.
- The next line creates an **NSRange** object called **range** that represents the entire length of the input text.
- The **tagger.enumerateTags(in:range, unit:.word, scheme:.lemma, options: options)** method is called to iterate over the words in the input text and extract their corresponding lemmas.
- Inside the enumeration block, the code retrieves the current word and its associated lemma using the tokenRange and tag parameters.
- The line **let word = (text as NSString).substring(with: tokenRange)** extracts the substring corresponding to the current word using **tokenRange**.
- Finally, the words array is returned, which contains all the extracted lemmas (words and their associated base forms) from the input text.

In summary, function **getLemmas** uses the **NSLinguisticTagger** to perform linguistic analysis on a given text and extract the base forms (lemmas) of words. The lemmas are then stored in an array of tuples and returned as the result of the function.

Here is some test code:

```swift
let quote = "President George Bush went to Mexico with IBM representatives. Here's to the crazy ones. The misfits. The rebels. The troublemakers. The round pegs in the square holes. The ones who see things differently. They're not fond of rules. And they have no respect for the status quo. You can quote them, disagree with them, glorify or vilify them. About the only thing you can't do is ignore them. Because they change things. They push the human race forward. And while some may see them as the crazy ones, we see genius. Because the people who are crazy enough to think they can change the world, are the ones who do. - Steve Jobs (Founder of Apple Inc.)"
if #available(OSX 10.13, *) {
            print("\nEntities:\n")
            print(getEntities(for: quote))
            print("\nLemmas:\n")
            print(getLemmas(for: quote))
}
```

Here is an edited listing of the output with most of the output removed for brevity:

```
Entities:

[("President", "OtherWord"), ("George Bush", "PersonalName"), ("went", "OtherWord"), ("to", "OtherWord"), ("Mexico", "PlaceName"), ("with", "OtherWord"), ("IBM", "OrganizationName"), 
  ...]

Lemmas:

[("President", "President"), ("George Bush", "George"), ("went", "go"), ("to", "to"), ("Mexico", "Mexico"),
  ...]
```