typedef void* (*call_fn)(void *ctx);
extern void *Async_FutureCreate();
extern void Async_FutureDestroy(void *Future);
extern void *Async_FutureWait(void *Future);
extern void Async_FutureSet(void *Future, void *value);
extern int Async_call(call_fn function, void *ctx, void *return_to);
extern int Async_updateSchedule();