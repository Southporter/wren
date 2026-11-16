# Wren

This is [Wren](https://wren.io/), packaged for [Zig](https://ziglang.org) with the [Zig build system](https://ziglang.org/intro/build-system/)


## Installation

First, add it to your Zig project:

```sh
zig fetch --save git+https://github.com/Southporter/wren.git#v0.1.0
```

Then, you can add it as module for your program:


```zig
const wren = b.dependency("wren", .{});

// Add as import to your module
root_module.addImport("wren", wren.module("wren"));
```

