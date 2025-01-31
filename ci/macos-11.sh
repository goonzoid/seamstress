#!/bin/sh

sudo mkdir /opt/zig
wget https://ziglang.org/builds/zig-macos-x86_64-0.11.0.tar.xz
tar -xf zig-macos-x86_64-0.11.0.tar.xz -C /tmp
sudo cp -R /tmp/zig-macos-x86_64-0.11.0/* /opt/zig
brew install freetype2 harfbuzz ncurses pkg-config
/opt/zig/zig build -Doptimize=ReleaseFast
