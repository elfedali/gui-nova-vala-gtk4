.PHONY: all build run clean install

all: build

build:
	@if [ ! -d "build" ]; then meson setup build; fi
	ninja -C build

run: build
	./build/src/nova

clean:
	rm -rf build

install: build
	ninja -C build install
