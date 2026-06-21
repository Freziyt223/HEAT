#include <Async.h>
#include <IO.h>
#include <stdlib.h>
// this will expose those functions to the engine
#define Engine __declspec(dllexport)

void *future = NULL;
void *wrapper(void *ctx) {
    // Because in C we can't pass types we have to allocate a cell and pass it's pointer to future,
    // then we can read the value by dereferencing and freeing the cell on our own
    int *returned = malloc(sizeof(int));
    IO_print("Hello, %s", "from other thread!\n");
    *returned = 0;
    return (void *)returned;
}

Engine int init() {
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

Engine void deinit() {
    Async_FutureDestroy(future);
}

