FROM ubuntu:latest

RUN apt-get update && apt-get install -y wget unzip

# Install stylua
RUN wget https://github.com/JohnnyMorganz/StyLua/releases/download/v0.20.0/stylua-linux-aarch64.zip \
    && unzip stylua-linux-aarch64.zip \
    && chmod +x stylua \
    && mv stylua /usr/local/bin/ \
    && rm stylua-linux-aarch64.zip

WORKDIR /app

ENTRYPOINT ["stylua"]