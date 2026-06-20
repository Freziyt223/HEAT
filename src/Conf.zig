//! If there is a null - default runtime value will be used
//! If you want to change any values do it with caution as this might break functionality
const std = @import("std");
pub const BuildOptions = @import("BuildOptions");

pub var GlobalAllocator: ?std.mem.Allocator = null;
/// Not including main thread
pub var NumberOfThreads: usize = 3;
/// MUST BE A POWER OF 2
pub var QueueCapacity_EVEN: usize = 8;

pub inline fn is_singlethreaded() bool {
    return BuildOptions.singlethreaded or NumberOfThreads == 0;
}
