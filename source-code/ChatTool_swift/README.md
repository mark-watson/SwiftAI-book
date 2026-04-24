# Chat Tool Using Apple Intelligence Local and falls back to Apple PCC Secure Cloud Model - Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

I have been experimenting with a macOS26 Apple Intelligence example chat command line tool that uses the local 3B model for most model calls, but if the local model is not powerful enough then Apple silently offloads it to Private Cloud Compute (PCC)—their secure Apple cloud—while maintaining encryption and privacy. There doesn't seem to be a way to tell when a remote model invocation is used. 

## Run

    swift build
    swift run

Note: **swift build** puts the executable in: .build/debug/chattool

```
swift build              .build/debug/<name>
swift build -c release   .build/release/<name>
```
