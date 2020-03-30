# Preface

Why use Swift for hacking AI? Common Lisp has been my go-to language for artificial intelligence development and research since 1982. The transition to using Swift was a slow transition for me. During this transition I prototyped a new product in parallel using both Swift and Common Lisp, weighing the advantages of both for my current requirements.

I have used Common Lisp for AI research projects and for AI product development and delivery since 1982. There is something special about using a language for almost forty years. All that said, I find Swift a compelling choice now for several reasons:

- Flexible language with many features I rely on like supporting closures and an interactive functional programming style.
- Builtin support for deep learning neural network models for natural language processing, predictive models, etc.
- First class support for iOS and macOS development.

Swift is a programmer-efficient language: code is concise and easy to read, and high quality libraries from Apple and third parties mean that often there is less code to write. I will share with you my Swift development work flow that combines interactive development of code in playgrounds, development of higher level libraries in text only or command line applications, and my general strategy for writing iOS and macOS applications after low level and intermediate code is written and debugged.

## Parts of this Book are Specific for macOS and iOS, with some support for Linux and Windows

Swift is a general purpose language that is well supported in macOS, iOS, and Linux, with some support in Windows. Here, we cover the use of Swift on macOS and iOS. Some of the examples in this book rely on libraries that are specifically available on macOS and iOS like CoreML and the NLP libraries. We will also be using TensorFlow for Swift and these examples also work on Linux, as do the examples using SQLite, the Microsoft Azure search APIs, web scraping, and semantic web/linked data.

## Author's Background

I live in Sedona Arizona with my wife and pet parrot. Our children and grandchildren live in California, Rhode Island, and the state of Washington.

I am motivated to write this book to support developers who want to use Swift for AI applications, we will start with a few non-AI examples because we will use this material in later examples. Specifically, we will cover command line applications, using the embedded SQLite database, and web scraping. For me, these are low level techniques that show up in many of my projects.

We will then look at the AI technologies that I have used throughout my career: knowledge representation using semantic web and linked data, machine learning and deep learning, and natural language processing. I am grateful for the companies where I have worked (SAIC, Google, Capital One, etc.) that have supported this work since 1982.

As an author, I hope that the material in this book entertains you and will be useful in your work.

## A Request from the Author

I spent time writing this book to help you, dear reader. I release this book under the Creative Commons "share and share alike, no modifications, no commercial reuse" license and set the minimum purchase price to $5.00 in order to reach the most readers. Under this license you can share a PDF version of this book with your friends and coworkers. If you found this book on the web (or it was given to you) and if it provides value to you then please consider doing one of the following to support my future writing efforts and also to support future updates to this book:

- Purchase a copy of [this book](https://leanpub.com/SwiftAI) or any other of my leanpub books at [https://leanpub.com/u/markwatson](https://leanpub.com/u/markwatson)
- [Hire me as a consultant](https://markwatson.com/)

I enjoy writing and your support helps me write new editions and updates for my books and to develop new book projects. Thank you!

## Acknowledgements

I thank my wife Carol for editing this manuscript, finding typos, and suggesting improvements.
