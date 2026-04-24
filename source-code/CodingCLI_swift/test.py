import os

from groq import Groq

client = Groq(
    api_key=os.environ.get("GROQ_API_KEY"),
)

chat_completion = client.chat.completions.create(
    messages=[
        {
            "role": "user",
            "content": "If Sally is 31 and Bil is 17 and Peter is 44, what are their age differences? Please be concise.",
        }
    ],
    model="llama3-8b-8192",
)



print(chat_completion.choices[0].message.content)
