#include <Async.h>
#include <IO.h>
#include <stdlib.h>

void *future = NULL;
void *wrapper(void *ctx) {
    int *returned = malloc(sizeof(int));
    IO_print("Hello, %s", "from other thread!\n");
    *returned = 0;
    return (void *)returned;
}

__declspec(dllexport) int init() {
    future = Async_FutureCreate();
    if (future == NULL) {
        IO_print("Couldn't create future!\n");
        return -2;
    }

    int returned = Async_call(&wrapper, NULL, future);
    if (returned != 0) {
        return returned;
    }
    void *returned2 = Async_FutureWait(future);
    if (returned2 != NULL) {
        IO_print("Got: %d", *(int*)returned2); 
        free(returned2);
    }
    return 0;
}

__declspec(dllexport) void deinit() {
    Async_FutureDestroy(future);
}

