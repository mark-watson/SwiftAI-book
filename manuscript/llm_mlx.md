# Using Apple's MLX Framework to Run Local LLMs

Apple's MLX framework is an efficient way to use LLMs embedded in applications for macOS, iOS, and iPadOS.

It is difficult to create simple command line Swift apps using MLX but there are several complete MLX, Swift, and SwiftUI demo applications. Here we will use the **LLMEval** application from the GitHub repository [https://github.com/ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples).

In the past I seldom used MLX but I am starting a side project using Swift, SwiftUI, and MLX. We will be using open weight models hosted by Hugging Face.

Getting a Hugging Face account is a straightforward step that unlocks access to a wealth of machine learning models, datasets, and tools, especially if you’re using MLX on macOS. Start by visiting the Hugging Face website [https://huggingface.co](https://huggingface.co) and clicking on “Sign Up” at the top right. You can create an account using your email address, or, for convenience, sign in with your GitHub, Google, or other supported accounts. Once registered, you’ll have access to a personal dashboard where you can manage your API tokens, repositories, and activities. These tokens are essential for integrating Hugging Face tools with local environments like MLX, allowing seamless access to models and datasets.

After setting up your account, grab your API token from your Hugging Face profile under “Settings” > “Access Tokens.” Copy this token and configure it in your MLX environment using a simple command like mlx login or by directly pasting the token in the MLX interface. I also set an environment variable with my Hugging Face API key:


{linenos=off}
~~~~~~~~
export HUGGINGFACEHUB_API_TOKEN=hf_oyPvW...not_my_key
~~~~~~~~

Apple’s MLX framework, introduced in December 2023, is a key part of Apple’s strategy to support AI on its hardware platforms by leveraging the unique capabilities of Apple Silicon, including the M1, M2, M3, and M4 series. Designed as an open-source, NumPy-like array framework, MLX optimizes machine learning workloads, particularly large language models (LLMs), by utilizing Apple Silicon’s unified architecture that integrates CPU, GPU, Neural Engine, and shared memory. This architecture eliminates data transfer bottlenecks, enabling faster and more efficient ML tasks, such as training and deploying LLMs directly on devices like MacBooks and iPhones. MLX aligns with Apple’s privacy-focused approach by supporting on-device processing, enhancing performance for applications like natural language processing, speech recognition, and content generation while offering a seamless transition for Python ML engineers familiar with frameworks like NumPy and PyTorch. MLX stands out by leveraging Apple’s unified memory architecture, allowing shared memory access between CPU and GPU, which eliminates data transfer overhead and accelerates machine learning tasks, especially with large datasets.

## MLX Resources on GitHub

In this chapter we will use a few simple Swift programs that use MLX. After working through these simple examples, the following resources on GitHub are worth looking at:

- https://github.com/ml-explore/mlx-swift: The Swift API for MLX, enabling integration with Swift-based projects.
- https://github.com/ml-explore/mlx-swift-examples: Examples showcasing the use of MLX with Swift.

These repositories provide a comprehensive set of tools and examples to effectively utilize MLX for machine learning tasks on Apple silicon. There are many other repositories for MLW and Python and if you need to perform tasks like fine tuning a MLX model, that task should probably be done using Python.


