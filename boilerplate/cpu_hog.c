#include <stdio.h>
#include <time.h>

int main() {
    printf("CPU hog started. Burning cycles for 30 seconds...\n");
    volatile unsigned long long count = 0;
    time_t start = time(NULL);
    while (time(NULL) - start < 30) {
        count++;
    }
    printf("CPU hog finished. Final count: %llu\n", count);
    return 0;
}