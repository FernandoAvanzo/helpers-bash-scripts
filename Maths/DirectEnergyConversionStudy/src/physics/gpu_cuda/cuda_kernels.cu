
# CUDA kernel scaffold (PyCUDA compatible)

__global__ void particle_push(float *x, float *v, float E, float dt, int N){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if(i < N){
        v[i] += E * dt;
        x[i] += v[i] * dt;
    }
}
