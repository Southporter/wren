const std = @import("std");
pub const c = @import("c");

pub const Config = struct {
    inner: c.WrenConfiguration = undefined,
    pub fn init(config: *Config) void {
        c.wrenInitConfiguration(&config.inner);
    }
};

pub const Vm = opaque {
    pub fn init(config: *Config) *Vm {
        return @ptrCast(c.wrenNewVM(&config.inner));
    }
    pub fn deinit(vm: *Vm) void {
        c.wrenFreeVM(@ptrCast(vm));
    }

    pub fn interpret(vm: *Vm, module: [:0]const u8, script: [:0]const u8) Result {
        const res = c.wrenInterpret(@ptrCast(vm), module.ptr, script.ptr);
        return @fromBackingInt(res);
    }

    pub fn call(vm: *Vm, handle: *Handle) Result {
        const res = c.wrenCall(@ptrCast(vm), @ptrCast(handle));
        return @fromBackingInt(res);
    }

    pub fn userdata(vm: *Vm) ?*anyopaque {
        return c.wrenGetUserData(@ptrCast(vm));
    }

    pub fn ensureSlots(vm: *Vm, count: usize) void {
        c.wrenEnsureSlots(@ptrCast(vm), @intCast(count));
    }
    pub fn setSlot(vm: *Vm, comptime T: type, slot: usize, val: T) void {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .bool => c.wrenSetSlotBool(@ptrCast(vm), @intCast(slot), val),
            .null => c.wrenSetSlotNull(@ptrCast(vm), @intCast(slot)),
            .float => c.wrenSetSlotDouble(@ptrCast(vm), @intCast(slot), val),
            .int => c.wrenSetSlotDouble(@ptrCast(vm), @intCast(slot), @floatFromInt(val)),
            else => @compileError("Unsupported type " ++ @typeName(T) ++ " provided to setSlot"),
        }
    }
pub fn getSlot(vm: *Vm, comptime T:type, slot: usize) T {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .bool => c.wrenGetSlotBool(@ptrCast(vm), @intCast(slot)),
        .float => |f| {
            const double = c.wrenGetSlotDouble(@ptrCast(vm), @intCast(slot));
            if (f.bits < 64) {
                return @floatCast(double);
            }
            return double;
        },
        .int => @as(T, @floatFromInt(getSlot(vm, f32, slot))),
        else => @compileError("Unsupported type " ++ @typeName(T) ++ "provided to getSlot"),
    };
}
    pub fn getSlotHandle(vm: *Vm, slot: usize) *Handle {
        return @ptrCast(c.wrenGetSlotHandle(@ptrCast(vm), @intCast(slot)));
    }
    pub fn setSlotHandle(vm: *Vm, slot: usize, handle: *Handle) void {
        c.wrenSetSlotHandle(@ptrCast(vm), @intCast(slot), @ptrCast(handle));
    }

    pub fn getVariable(vm: *Vm, module: [:0]const u8, name: [:0]const u8, slot: usize) void {
        c.wrenGetVariable(@ptrCast(vm), module.ptr, name.ptr, @intCast(slot));
    }

    pub fn makeCallHandle(vm: *Vm, sig: [:0]const u8) ?*Handle {
        return @ptrCast(c.wrenMakeCallHandle(@ptrCast(vm), sig.ptr));
    }
};

pub const Handle = opaque {};
pub const Result = enum(c.WrenInterpretResult) {
    success = c.WREN_RESULT_SUCCESS,
    compile_error = c.WREN_RESULT_COMPILE_ERROR,
    runtime_error = c.WREN_RESULT_RUNTIME_ERROR,
};

pub const Error = enum(c.WrenErrorType) {
    compile = c.WREN_ERROR_COMPILE,
    runtime = c.WREN_ERROR_RUNTIME,
    stack_trace = c.WREN_ERROR_STACK_TRACE,
};

fn errorFn(vm_c: ?*c.WrenVM, err_c: c.WrenErrorType, module_c: [*c]const u8, line: c_int, msg_c: [*c]const u8) callconv(.c) void {
    const vm: *Vm = @ptrCast(vm_c);
    const module = if (module_c) |mod| std.mem.span(mod) else "";
    const msg = std.mem.span(msg_c);
    const err: Error = @fromBackingInt(err_c);
    const context: *TestContext = @ptrCast(@alignCast(vm.userdata().?));
    switch (err) {
        .compile => {
            context.err_writer.print("[{s} line {d}] CompileError: {s}\n", .{ module, line, msg }) catch {};
        },
        .runtime => {
            context.err_writer.print("RuntimeError: {s}\n", .{msg}) catch {};
        },
        .stack_trace => {
            context.err_writer.print("[{s} line {d}] in {s}\n", .{ module, line, msg }) catch {};
        },
    }
}
fn writeFn(vm_c: ?*c.WrenVM, text: [*c]const u8) callconv(.c) void {
    const vm: *Vm = @ptrCast(vm_c);
    const context: *TestContext = @ptrCast(@alignCast(vm.userdata().?));
    context.writer.writeAll(std.mem.span(text)) catch {};
}

const TestContext = struct {
    writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
};

test {
    var config = Config{};
    config.init();

    var logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer logger.deinit();
    var err_logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_logger.deinit();
    var context: TestContext = .{
        .writer = &logger.writer,
        .err_writer = &err_logger.writer,
    };
    config.inner.userData = &context;

    config.inner.errorFn = errorFn;
    config.inner.writeFn = writeFn;

    var vm = Vm.init(&config);
    defer vm.deinit();
    const msg = "I'm running in the vm!";

    const res = vm.interpret("main", "System.print(\"" ++ msg ++ "\")");
    try std.testing.expectEqual(.success, res);
    try std.testing.expectEqualStrings(msg ++ "\n", logger.written());
    try std.testing.expectEqualStrings("", err_logger.written());
}

test "Method call" {
    var config = Config{};
    config.init();

    var logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer logger.deinit();
    var err_logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_logger.deinit();
    var context: TestContext = .{
        .writer = &logger.writer,
        .err_writer = &err_logger.writer,
    };

    config.inner.userData = &context;
    config.inner.writeFn = writeFn;
    config.inner.errorFn = errorFn;

    var vm = Vm.init(&config);
    defer vm.deinit();

    const script =
        \\class GameEngine {
        \\  static update(elapsedTime) {
        \\    System.print("Elapsed time is " + elapsedTime.toString)
        \\  }
        \\}
    ;
    const res = vm.interpret("main", script);
    try std.testing.expectEqual(.success, res);

    vm.ensureSlots(2);
    vm.getVariable("main", "GameEngine", 0);
    const gameEngineClass = vm.getSlotHandle(0);
    vm.setSlotHandle(0, gameEngineClass);
    const updateHandle = vm.makeCallHandle("update(_)");

    // vm.setSlotHandle(0, updateHandle.?);
    const elapsedTime: f32 = 1;
    vm.setSlot(f32, 1, elapsedTime);

    try std.testing.expectEqualStrings("", err_logger.written());
    try std.testing.expectEqual(.success, vm.call(updateHandle.?));
    try std.testing.expectEqualStrings("Elapsed time is 1\n", logger.written());
}

fn foreignMethodHandler(vm: ?*c.WrenVM, module_c: [*c]const u8, class_name_c: [*c]const u8, is_static: bool, sig_c: [*c]const u8) callconv(.c) c.WrenForeignMethodFn {
    _ = vm;
    const module = std.mem.span(module_c);
    const class_name = std.mem.span(class_name_c);
    const sig = std.mem.span(sig_c);
    if (std.mem.eql(u8, module, "main") and std.mem.eql(u8, class_name, "Math") and std.mem.eql(u8, sig, "add(_,_)")) {
        std.debug.assert(is_static);
        return mathAdd;
    }
    return null;
}
fn mathAdd(vm_c: ?*c.WrenVM) callconv(.c) void {
    const vm: *Vm = @ptrCast(vm_c);
    const a = vm.getSlot(f32, 1);
    const b = vm.getSlot(f32, 2);
    vm.setSlot(f32, 0, a + b);
}

test "Foreign methods" {
    var config = Config{};
    config.init();

    var logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer logger.deinit();
    var err_logger: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer err_logger.deinit();
    var context: TestContext = .{
        .writer = &logger.writer,
        .err_writer = &err_logger.writer,
    };
    config.inner.userData = &context;
    config.inner.writeFn = writeFn;
    config.inner.errorFn = errorFn;
    config.inner.bindForeignMethodFn = foreignMethodHandler;

    var vm = Vm.init(&config);
    defer vm.deinit();

    const script =
        \\class Math {
        \\  foreign static add(a, b)
        \\}
    ;
    const res = vm.interpret("main", script);
    try std.testing.expectEqual(.success, res);
    vm.ensureSlots(3);
    vm.getVariable("main", "Math", 0);
    const math_class_handle = vm.getSlotHandle(0);
    vm.setSlotHandle(0, math_class_handle);
    const updateHandle = vm.makeCallHandle("add(_,_)");
    vm.setSlot(f32, 1, 1);
    vm.setSlot(f32, 2, 2);

    const call_res = vm.call(updateHandle.?);
    try std.testing.expectEqual(.success, call_res);
    const sum = vm.getSlot(f64, 0);
    try std.testing.expectApproxEqRel(3, sum, 0.0001);
    try std.testing.expectEqualStrings("", err_logger.written());
    try std.testing.expectEqualStrings("", logger.written());
}
