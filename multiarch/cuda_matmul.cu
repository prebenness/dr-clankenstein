#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static const int N = 64;

__global__ void matmul_kernel(const float *a, const float *b, float *c, int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (row >= n || col >= n) {
        return;
    }
    float sum = 0.0f;
    for (int k = 0; k < n; ++k) {
        sum += a[row * n + k] * b[k * n + col];
    }
    c[row * n + col] = sum;
}

static void json_string(const char *value) {
    std::putchar('"');
    if (value != nullptr) {
        for (const char *p = value; *p; ++p) {
            if (*p == '"' || *p == '\\') {
                std::putchar('\\');
            }
            if (*p >= 32 && *p < 127) {
                std::putchar(*p);
            }
        }
    }
    std::putchar('"');
}

static const char *env_value(const char *key) {
    const char *value = std::getenv(key);
    return value == nullptr ? "" : value;
}

static void fail(cudaError_t err, const char *expr, const char *file, int line) {
    std::fprintf(stderr, "CUDA error at %s:%d: %s: %s\n", file, line, expr, cudaGetErrorString(err));
    std::exit(1);
}

#define CHECK(expr) do { cudaError_t err__ = (expr); if (err__ != cudaSuccess) fail(err__, #expr, __FILE__, __LINE__); } while (0)

int main() {
    int count = 0;
    CHECK(cudaGetDeviceCount(&count));
    if (count < 1) {
        std::fprintf(stderr, "No CUDA devices visible\n");
        return 1;
    }

    int device = 0;
    cudaDeviceProp prop {};
    CHECK(cudaGetDeviceProperties(&prop, device));
    CHECK(cudaSetDevice(device));

    const int elements = N * N;
    const size_t bytes = elements * sizeof(float);
    float *h_a = static_cast<float *>(std::malloc(bytes));
    float *h_b = static_cast<float *>(std::malloc(bytes));
    float *h_c = static_cast<float *>(std::malloc(bytes));
    if (!h_a || !h_b || !h_c) {
        std::fprintf(stderr, "Host allocation failed\n");
        return 1;
    }

    for (int i = 0; i < elements; ++i) {
        h_a[i] = 1.0f;
        h_b[i] = 2.0f;
        h_c[i] = 0.0f;
    }

    float *d_a = nullptr;
    float *d_b = nullptr;
    float *d_c = nullptr;
    CHECK(cudaMalloc(&d_a, bytes));
    CHECK(cudaMalloc(&d_b, bytes));
    CHECK(cudaMalloc(&d_c, bytes));
    CHECK(cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice));

    dim3 block(16, 16);
    dim3 grid((N + block.x - 1) / block.x, (N + block.y - 1) / block.y);
    matmul_kernel<<<grid, block>>>(d_a, d_b, d_c, N);
    CHECK(cudaGetLastError());
    CHECK(cudaDeviceSynchronize());
    CHECK(cudaMemcpy(h_c, d_c, bytes, cudaMemcpyDeviceToHost));

    double max_abs_error = 0.0;
    const double expected = 2.0 * N;
    for (int i = 0; i < elements; ++i) {
        max_abs_error = std::fmax(max_abs_error, std::fabs(static_cast<double>(h_c[i]) - expected));
    }
    bool ok = max_abs_error < 1e-4;

    std::printf("{\"ok\":%s,\"backend\":\"cuda\",\"device_count\":%d,\"device_name\":", ok ? "true" : "false", count);
    json_string(prop.name);
    std::printf(",\"compute_capability\":\"%d.%d\",\"n\":%d,\"max_abs_error\":%.9g,\"node\":", prop.major, prop.minor, N, max_abs_error);
    json_string(env_value("SLURMD_NODENAME"));
    std::printf(",\"partition\":");
    json_string(env_value("SLURM_JOB_PARTITION"));
    std::printf(",\"job_id\":");
    json_string(env_value("SLURM_JOB_ID"));
    std::printf("}\n");

    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    std::free(h_a);
    std::free(h_b);
    std::free(h_c);
    return ok ? 0 : 1;
}
