# Introduction to Swift

Swift is a general purpose language that is well supported in macOS and iOS, with good support for Linux, and with some support in Windows. For the purposes of this book, we are only considering the use of Swift on macOS and iOS. Most of the examples in this book rely on libraries that are specifically available on macOS and iOS like CoreML and the NLP libraries. We will also be using TensorFlow for Swift and these examples also work on Linux.

There are great free resources for the Swift language on the web, in other commercial books, and Apple's free Swift books. Here I provide just enough material on the Swift language for you to understand and work with the book examples. After working through this book's material you will be able to add machine learning, natural language processing, and knowledge representation to your applications. There will be parts of the Swift language that we don't need for the material here, and we won't cover.

TBD

## Installing Swift Packages

We will use the [SwiftBrew package manager](https://github.com/swiftbrew/Swiftbrew) so please install SwiftBrew right now following directions for your operating system.


We will use [https://vapor.codes](https://vapor.codes) as an example. Start by cloning the git repository [https://github.com/vapor/vapor](https://github.com/vapor/vapor). Then:

{linenos=off}
~~~~~~~~
git clone https://github.com/vapor/vapor.git
cd vapor
swift build
~~~~~~~~

Then in a Swift repl you can use the library:

{linenos=off}
~~~~~~~~

~~~~~~~~

## Creating Swift Packages

We will cover using the Swift Package Manager using the command line here. Later we will create projects using Apple's XCode IDE when we devlop the example application Knowledge Graph Navigator.

You will want to use the [Swift Package Manager documentation](https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md) for reference.

We will be generting executable projects and library (with a sample main program) projects. The commands for generating an executable application project is

{linenos=off}
~~~~~~~~
mkdir BingSearch
cd BingSearch
swift package init --type executable
~~~~~~~~

and build a library with a demo main program:

{linenos=off}
~~~~~~~~
mkdir SparqlQuery
cd SparqlQuery
swift package init --type library
~~~~~~~~




## Primer of Swift Language Features that You Will Need to Know to Use this Book

TBD

## Advice for Integrating AI Technologies Into Your Work

TBD

## AI Technologies Related to Privacy and Promoting Good in Society

TBD

## Tips for Using AI Technology Without the Resources of Large Companies Like Google, Baidu, Microsoft, Tencent, and Amazon

TBD
