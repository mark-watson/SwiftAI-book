# Cover Material, Copyright, and License

Copyright 2022 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/lovinglisp
```

This eBook will be updated occasionally so please periodically check the [leanpub.com web page for this book](https://leanpub.com/SwiftAI) for updates.

This is the first edition released spring of 2022.

Please visit the [author's website](http://markwatson.com).

If you found a copy of this book on the web and find it of value then please consider buying a copy at [leanpub.com/SwiftAI](https://leanpub.com/SwiftAI) to support the author and fund work for future updates.  You can also see all of my books on [my website https://markwatson.com/#books](https://markwatson.com/#books).


# Preface

Why use Swift for hacking AI? Common Lisp has been my go-to language for artificial intelligence development and research since 1982. The transition to using Swift was a slow transition for me. During this transition I prototyped a new project in parallel using both Swift and Common Lisp, weighing the advantages of both for my current requirements. The Swift version of this project included in this book runs on macOS, iOS, and iPadOS. The macOS version is available on the Apple Store. Several of the utilities developed in this book were used in this project.

This book starts out slowly with simple examples which I wrote showing how to access the Swift library packages on GitHub, tips on writing Swift command line apps, and web scraping. We then proceed to using Apple's CoreML for Natural Language Processing (NLP), training and using your own CoreML models, using OpenAI's GPT-3 APIs, and finally several semantic web/linked data examples. The book ends with the example [KGN on the App Store](https://apps.apple.com/us/app/kgn/id1514197947?mt=12). It is not my intention to cover in detail the use of SwiftUI for building iOS/iPadOS/macOS applications but I thought my readers might enjoy seeing several of the techniques covered in the book integrated into an example app.

I have used Common Lisp for AI research projects and for AI product development and delivery since 1982. There is something special about using a language for almost forty years. All that said, I find Swift a compelling choice now for several reasons:

- Flexible language with many features I rely on like supporting closures and an interactive functional programming style.
- Built in support for deep learning neural network models for natural language processing, predictive models, etc.
- First class support for iOS and macOS development.
- Good support for server side applications hosted on Linux.

Swift is a programmer-efficient language: code is concise and easy to read, and high quality libraries from Apple and third parties mean that often there is less code to write. I will share with you my Swift development work flow that combines interactive development of code in playgrounds, development of higher level libraries in text only or command line applications, and my general strategy for writing iOS and macOS applications after low level and intermediate code is written and debugged.

## Parts of this Book are Specific for macOS and iOS, with Some Support for Linux

Swift is a general purpose language that is well supported in macOS, iOS, and Linux, with some support in Windows. Here, we cover the use of Swift on macOS and iOS. Some of the examples in this book rely on libraries that are specifically available on macOS and iOS like CoreML and the NLP libraries. Several book examples also work on Linux, such as the examples using SQLite, the Microsoft Azure search APIs, web scraping, and semantic web/linked data.

## Code for this Book

Because of the way the Swift Package Manager works, I organized all book examples that build libraries as separate GitHub repos so the libraries can be easily used in other book examples as well as your own software projects. The separate library GitHub repositories are:

- [https://github.com/mark-watson/SparqlQuery_swift](https://github.com/mark-watson/SparqlQuery_swift) - SPARQL Swift library for my Swift AI book.
- [https://github.com/mark-watson/QuestionAnswering_BERT_swift](https://github.com/mark-watson/QuestionAnswering_BERT_swift) - modification of Apple's question answering demo to use DBPedia.
- [https://github.com/mark-watson/swift-coreml-wisconsin_data_create_model](https://github.com/mark-watson/swift-coreml-wisconsin_data_create_model) - create CoreML models from training data files of Wisconsin Caner data.
- [https://github.com/mark-watson/swift-coreml-wisconsin_data_predict_with_model](https://github.com/mark-watson/swift-coreml-wisconsin_data_predict_with_model) - use the pretrained Wisconsin Cancer data model.
- [https://github.com/mark-watson/ShellProcess_swift](https://github.com/mark-watson/ShellProcess_swift) - library for spawning shell processes and capturing output to stdout.
- [https://github.com/mark-watson/WebScraping_swift](https://github.com/mark-watson/WebScraping_swift) - library for scrapping web sites.
- [https://github.com/mark-watson/OpenAI_swift](https://github.com/mark-watson/OpenAI_swift) - library for using OpenAI's GPT3 APIs.
- [https://github.com/mark-watson/Nlp_swift](https://github.com/mark-watson/Nlp_swift) - library that uses pretrained CoreML NLP models.
- [https://github.com/mark-watson/KGN](https://github.com/mark-watson/KGN) - SwiftUI based application supporting macOS, iPadOS, and iOS. The macOS version is in Apple's app store.

I suggest cloning all of these GitHub repositories right now so you can have the example source code at hand while reading this book.

All of the code examples are licensed using the Apache 2 license. You are free to reuse the book example code in your own projects (open source, commercial), with attribution of my copyright and the Apache 2 license.

Except for the last SwiftUI example application, all sample programs are written as command line utilities. I considered using Swift playgrounds for some of the examples but decided that packaging as a combination of libraries and command line utilities would tend to make the example code more useful for your own projects.

http://www.knowledgegraphnavigator.com/

## Author's Background

I live in Sedona, Arizona with my wife and pet parrot. Our children and grandchildren live in California, Rhode Island, and the state of Washington.

I have written 20+ books, mostly about artificial intelligence. I have over 50 US patents.

I write about technologies that I have used throughout my career: knowledge representation using semantic web and linked data, machine learning and deep learning, and natural language processing. I am grateful for the companies where I have worked (SAIC, Google, Capital One, Olive AI, Babylist, etc.) that have supported this work since 1982.

As an author, I hope that the material in this book entertains you and will be useful in your work.

## A Request from the Author

I spent time writing this book to help you, dear reader. I release this book under the Creative Commons license and set the minimum purchase price to **Free** in order to reach the most readers. If you found this book on the web (or it was given to you) and if it provides value to you then please consider doing the following to support my future writing efforts and also to support future updates to this book:

- Purchase a copy of [this book](https://leanpub.com/SwiftAI) or any other of my leanpub books at [https://leanpub.com/u/markwatson](https://leanpub.com/u/markwatson)

I enjoy writing and your support helps me write new editions and updates for my books and to develop new book projects. Thank you!

## Cover Art

The cover picture was taken by [WikiMedia Commons user Keta](https://commons.wikimedia.org/wiki/User:Keta) and is available for use under the Creative Commons License CC BY-SA 2.5.


## CoreML Libraries Used in this Book

- CoreML general overview: https://developer.apple.com/documentation/coreml
- MLClassifier https://developer.apple.com/documentation/createml/mlclassifier
- MLTextClassifier https://developer.apple.com/documentation/createml/mltextclassifier
- NLModel https://developer.apple.com/documentation/naturallanguage/nlmodel
- Natural Language Framework https://developer.apple.com/documentation/naturallanguage
- MLCustomLayer https://developer.apple.com/documentation/coreml/mlcustomlayer

## Swift 3rd Party Libraries

We use the following 3rd party libraries:

- [https://github.com/SwiftyJSON/SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON)

## Acknowledgements

I thank my wife Carol for editing this manuscript, finding typos, and suggesting improvements.
