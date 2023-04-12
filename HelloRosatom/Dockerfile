FROM alpine

WORKDIR /hello
COPY name.txt .

CMD ["/bin/sh", "-c", "echo Hello, Rosatom! Greetings from $(cat name.txt)"]