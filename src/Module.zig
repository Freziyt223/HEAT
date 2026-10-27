//! Selects between a real module and a manually maintained API-compatible stub.
const std = @import("std");

pub const NotImplemented = error.NotImplemented;

/// The stub type must explicitly implement every declaration its callers use.
pub fn wrap(
    comptime enabled: bool,
    comptime Implementation: type,
    comptime Stub: type,
) type {
    return if (enabled) Implementation else Stub;
}

/// Shared fallback policy for manually written stub functions.
/// Error-union return types must include `error.NotImplemented`.
pub fn fallback(comptime ReturnType: type) ReturnType {
    if (ReturnType == void) return;
    if (@typeInfo(ReturnType) == .error_union) return error.NotImplemented;
    return std.mem.zeroes(ReturnType);
}
