# Setting Up Swift For Command Line Development

Except for the last chapter that uses Xcode for developing a complete macOS/iOS/iPadOS example application, I assume that you will work through the book examples using the command line and your favorite editor. If you want to use Xcode for the command line examples, you can open the Swift package file on the command line and open Xcode using, for example:

{linenos=off}
~~~~~~~~
cd SparqlQuery_swift
open Package.swift
~~~~~~~~

You notice that most of the examples are command line apps or libraries with command line test programs and the **README.md** files in the example directories provide instructions for building and running on the command line.

You can also run Xcode and from the File Menu open an example's  **Package.swift** file. You can then use the Product / Test menu to run the test code for the example. You might need to use the View / Debug Area / Active Console menu to show the output area.

I assume that you are familiar with the Swift programming language and Xcode.

Swift is a general purpose language that is well supported in macOS and iOS, with good support for Linux, and with some support in Windows. For the purposes of this book, we are only considering the use of Swift on macOS and iOS. Most of the examples in this book rely on libraries that are specifically available on macOS and iOS like CoreML and the NLP libraries.

There are great free resources for the Swift language on the web, in other commercial books, and Apple's free Swift books. Here I provide just enough material on the Swift language for you to understand and work with the book examples. After working through this book's material you will be able to add machine learning, natural language processing, and knowledge representation to your applications. There will be parts of the Swift language that we don't need for the material here, and we won't cover.

## Installing Swift Packages

We will use the [Swift Package Manager](https://swift.org/package-manager/). You should pause reading now and install the Swift Package Manager if you have not already done so.

We occasionally use [https://vapor.codes web framework](https://vapor.codes) library (although not in this book). We use this 3rd party library as an example for building a library locally from source code. Start by cloning the git repository [https://github.com/vapor/vapor](https://github.com/vapor/vapor). Then:

{linenos=off}
~~~~~~~~
git clone https://github.com/vapor/vapor.git
cd vapor
swift build
~~~~~~~~

I don't usually install libraries locally from source code unless I am curious about the implementation and want to read through the source code. Later we will see how to reference Swift libraries hosted on GitHub in a project's **Package.swift** file.

## Creating Swift Packages

We will cover using the Swift Package Manager to create new packages using the command line here. Later we will create projects using Apple's XCode IDE when we develop the example application Knowledge Graph Navigator.

You will want to use the [Swift Package Manager documentation](https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md) for reference.

We will be generating executable projects and library (with a sample main program) projects. The commands for generating an executable application project are:

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

## Accessing Libraries that You Write in Other Projects

You can reference Swift libraries using the **Swift.package** file for each of your projects. We will look at parts of two **Swift.package** files here. The first is for my SPARQL query client library that we will develop in a later chapter. This library **SparqlQuery_swift** is used in both book examples Knowledge Graph Navigator (**KGN**) macOS/iOS/iPadOS example application as well as a text version **KnowledgeGraphNavigator_swift**.

{lang=swift, linenos=on}
~~~~~~~~
import PackageDescription

let package = Package(
    name: "SparqlQuery_swift",
    products: [
        .library(
            name: "SparqlQuery_swift",
            targets: ["SparqlQuery_swift"]),
    ],
    dependencies: [
      .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git",
          .branch("master")),
   ],
    targets: [
        .target(
            name: "SparqlQuery_swift",
            dependencies: ["SwiftyJSON"]),
        .testTarget(
            name: "SparqlQuery_swiftTests",
            dependencies: ["SparqlQuery_swift", "SwiftyJSON"]),
    ]
)
~~~~~~~~

The **Swift.package** file for text version **KnowledgeGraphNavigator_swift** is shown here:

{lang=swift, linenos=on}
~~~~~~~~
import PackageDescription

let package = Package(
    name: "KnowledgeGraphNavigator_swift",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git",
            .branch("master")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "1.7.4"),
        .package(url: "git@github.com:mark-watson/SparqlQuery_swift.git",
            .branch("main")),
        .package(url: "git@github.com:mark-watson/Nlp_swift.git", .branch("main")),
    ],
    targets: [
        // Targets are the basic building blocks of a package.
        // A target can define a module or a test suite.
        // Targets can depend on other targets in this package,
        // and on products in packages this package depends on.
        .target(
            name: "KnowledgeGraphNavigator_swift",
            dependencies: ["SparqlQuery_swift", "Nlp_swift",
              "SwiftyJSON", "SwiftSoup"]),
    ]
)
~~~~~~~~


Hopefully you have cloned the git repositories for each book example and understand how I have configured the examples for your use.

For the rest of this book, you can read chapters in any order. In some cases, earlier chapters will contain implementations of libraries used in later chapters.