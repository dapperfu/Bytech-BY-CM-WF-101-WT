CC = arm-linux-gnueabihf-gcc
CFLAGS = -std=c89 -Wall -Wextra -O2 -static
TARGET = hello
SRC = hello.c
OUTPUT_DIR = ../bin

all: $(OUTPUT_DIR)/$(TARGET)

$(OUTPUT_DIR)/$(TARGET): $(SRC) | $(OUTPUT_DIR)
	$(CC) $(CFLAGS) -o $@ $(SRC)

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

clean:
	rm -f $(OUTPUT_DIR)/$(TARGET)

.PHONY: all clean

