// A C++ callback throws through the library call.
#include <cstdio>
#include <stdexcept>

extern "C" void lib_call(void (*cb)());

static void callback() {
        throw std::runtime_error("thrown by the callback");
}

int main() {
        setvbuf(stdout, nullptr, _IONBF, 0);
        try {
                lib_call(callback);
                puts("main: lib_call returned");
        } catch (const std::exception &e) {
                printf("main: caught \"%s\"\n", e.what());
        }
        return 0;
}
