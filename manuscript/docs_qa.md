# Documents Question Answering Using OpenAI GPT3 APIs and a Local Embeddings Vector Database

The examples in this chapter are inspired by the Python LangChain and LlamaIndex projects, with just the parts I need for my projects written from scratch in Common Lisp. I wrote a Python book “LangChain and LlamaIndex Projects Lab Book: Hooking Large Language Models Up to the Real World Using GPT-3, ChatGPT, and Hugging Face Models in Applications” in March 2023: https://leanpub.com/langchain that you might also be interested in.

The GitHub repository for this example can be found here: TBD


## Implementing a Local Vector Database for Document Embeddings

TBD: change function names:


In the following listing of the file docs-qa.lisp we start in lines 6-31 with a few string utility functions we will need: write-floats-to-string, read-file, concat-strings, truncate-string, and break-into-chunks.

The function break-into-chunks is a work in progress. For now we simply cut long input texts into specific chunk lengths, often cutting words in half. A future improvement will be detecting sentence boundaries and breaking text on sentences. The Python libraries LangChain and LlamaIndex have multiple chunking strategies.


TBD

## Using Local Embeddings Vector Database With OpenAI GPT APIs

TBD



## Testing Local Embeddings Vector Database With OpenAI GPT APIs

TBD: update for Swift:

In the next part of the listing of docs-qa.lisp we write a test function to create two documents. The two calls to create-document actually save text and embeddings for about 20 text chunks in the database.


TBD

The output is (with a lot of debug printout not shown):

TBD


## Wrap Up for Using Local Embeddings Vector Database to Enhance the Use of GPT3 APIs With Local Documents

As I write this in early April 2023, I have been working almost exclusively with OpenAI APIs for the last year and using the Python libraries for LangChain and LlamaIndex for the last three months.

I started writing the examples in this chapter for my own use, implementing a tiny subset of the LangChain and LlamaIndex libraries in Swift in order to write efficient command line utilities for creating local embedding vector data stores and for interactive chat using my own data.

By writing about my “scratching my own itch” command line experiments here I hope that I get pull requests for https://github.com/mark-watson/Docs_QA_Swift from readers who are interested in helping to extend this code with new functionality.


